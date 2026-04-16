## Summary
- change Building unlock requirements from rank F to rank F-compatible any-completion behavior
- keep shotgun and frag grenade unlock checks aligned with issue #1826
- update unlock-manager tests to cover Building completion on any rank, including F

## Testing
- attempted targeted GUT run for `tests/unit/test_unlock_manager.gd`
- result: could not run in this checkout because `godot` is not installed in the local environment; CI uses the repository workflow command with the bundled Godot binary

Fixes #1826
