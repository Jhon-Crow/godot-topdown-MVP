# Issue 1818 Case Study

Collected artifacts:
- `game_log_20260415_212808.txt`: first owner report log for grenade tutorial sequencing.
- `game_log_20260416_032144.txt`: owner feedback log for step completion timing and missing final-step highlight.
- `game_log_20260416_095831.txt`: latest owner feedback log where `[дёрнуть вправо]` and `[отпустить ПКМ]` were crossed out together after the right flick.
- `game_log_20260416_102846.txt`: follow-up owner log for the remaining "not fixed" report after the previous attempt.
- `owner-feedback.png`: screenshot from the owner feedback thread.

Timeline:
- 2026-04-15: owner reported the grenade hint should require `G+ПКМ`, combine the right flick and RMB release in the visual instruction, and roll back when preparation is canceled before activation.
- 2026-04-16 03:21: owner reported steps should be crossed out strictly after their own actions and highlighted strictly sequentially.
- 2026-04-16 09:58: owner reported the right flick and RMB release actions were both crossed out immediately after the right flick, causing all later steps to appear one action early.
- 2026-04-16 10:28: owner confirmed the prior fix still did not correct the visible progression.
- 2026-04-16 16:35: owner repeated that `[дёрнуть мышкой]` and `[отпустить ПКМ]` were both crossed after the mouse flick, and requested English localization for the grenade tutorial hint.

Root cause:
- The hint text displays `[дёрнуть мышкой вправо] [отпустить ПКМ]` as adjacent actions, but the previous display builder treated them as one highlighted part.
- After the mouse flick, the builder advanced to the next displayed part, so `[отпустить ПКМ]` stopped being highlighted before the actual RMB release.
- Cancellation reset the internal step counter, but the strikethrough animation helper ignored lower target progress. The visible strike line could therefore stay advanced after rollback and make later attempts look one action early.
- The final RMB release path could also push the hint back from the final throw step to `[отпустить G]` if the throw signal had not dismissed the hint yet.
- The grenade hint strings were hardcoded in Russian in both tutorial level scripts, so English locale could not translate the new step text.

Fix direction:
- Track and render six sequential action tokens: hold `G+ПКМ`, flick right, release RMB, hold RMB again, release G, aim/release RMB.
- Compute strikethrough progress from the completed action-token text instead of fixed five-group percentages.
- Allow the strikethrough progress animation to move backward on cancellation, and cancel stale forward tweens when rollback starts.
- Keep the final throw step highlighted until the grenade-thrown signal dismisses the hint.
- Replace hardcoded Russian grenade hint strings with translation keys in `resources/translations/translations.csv`.

External reference:
- Godot's official `Input` documentation states that `is_action_pressed()` tracks the held state, while `is_action_just_pressed()` and `is_action_just_released()` are one-frame/tick edge checks. This supports modeling the tutorial as ordered state transitions from held state plus RMB press/release edges: https://docs.godotengine.org/en/stable/classes/class_input.html
