# Issue 1818 Case Study

Collected artifacts:
- `game_log_20260415_212808.txt`: first owner report log for grenade tutorial sequencing.
- `game_log_20260416_095831.txt`: latest owner feedback log where `[дёрнуть вправо]` and `[отпустить ПКМ]` were crossed out together after the right flick.
- `owner-feedback.png`: screenshot from the owner feedback thread.

Timeline:
- 2026-04-15: owner reported the grenade hint should require `G+ПКМ`, combine the right flick and RMB release in the visual instruction, and roll back when preparation is canceled before activation.
- 2026-04-16 03:21: owner reported steps should be crossed out strictly after their own actions and highlighted strictly sequentially.
- 2026-04-16 09:58: owner reported the right flick and RMB release actions were both crossed out immediately after the right flick, causing all later steps to appear one action early.

Root cause:
- The hint text visually groups `[дёрнуть мышкой вправо] [отпустить ПКМ]`, but the tutorial state machine needs to track those as two separate actions.
- The previous display builder mapped progress directly to the five visual groups, so progress after the right flick advanced far enough to visually complete both grouped actions.

Fix direction:
- Keep the reviewed five visual text groups.
- Track six action states internally: hold `G+ПКМ`, flick right, release RMB, hold RMB again, release G, aim/release RMB.
- Drive strikethrough progress from the six action states so only the right-flick portion completes after the flick, and the RMB release completes only after the actual release.
