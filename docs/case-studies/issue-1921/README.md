# Issue 1921 Case Study: log files still created by default

## Evidence

- User report from PR 1922 on 2026-05-03: after deleting data, the game still writes a log file by default.
- Downloaded log: `evidence/game_log_20260504_020648.txt`.

The first lines of the user log show a new exported Windows run creating
`game_log_20260504_020648.txt` next to the executable at startup. The
`ExperimentalSettings` initialization line in that same log includes
`Logging: true`, which means the file logger was re-enabled by loaded settings
before gameplay events happened.

## Timeline

1. Issue 1921 requested disabling file log creation by default and renaming the
   visible Experimental menu to Dev.
2. The first PR change set `FileLogger` and `ExperimentalSettings` defaults to
   disabled.
3. A later user test on 2026-05-04 at 02:06:48 local time still produced
   `game_log_20260504_020648.txt`.
4. The attached log showed `Logging: true` during `ExperimentalSettings`
   startup, proving the effective runtime setting was still enabled despite the
   source default being false.

## Root Cause

The original fix changed only the in-code default. Existing
`user://experimental_settings.cfg` files can still contain
`logging_enabled=true`, and `_load_settings()` restored that value. Because
`ExperimentalSettings._ready()` immediately calls
`FileLogger.set_logging_enabled(logging_enabled)`, a legacy saved true value
created a fresh log file on startup.

This is consistent with Godot's documented data model:

- `user://` points to a persistent per-project user data directory and is
  guaranteed writable in exported projects.
- For executable-adjacent files in exported desktop builds, Godot recommends
  using `OS.get_executable_path().get_base_dir()`.

`FileLogger` intentionally writes beside the executable first, so once the
legacy setting restored `Logging: true`, the startup log file creation was
expected behavior.

## Fix

`ExperimentalSettings` now stores a `settings_schema_version`. When loading a
pre-versioned settings file, it migrates `logging_enabled` to `false` and saves
the migrated config. This preserves the Dev menu toggle for users who enable
logging after the migration, while preventing old saved values from keeping log
recording on by default.

## Verification

- Added a unit test for migrating legacy saved `logging_enabled=true` to
  disabled.
- Existing tests continue to cover explicit opt-in persistence for current
  schema settings.
