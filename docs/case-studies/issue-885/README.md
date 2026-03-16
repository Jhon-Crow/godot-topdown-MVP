# Issue #885 Case Study: CRITICAL — File Logger Batch Flush

## Issue Description

**Title**: fix CRITICAL: File Logger Batch Flush

**Summary**: `FileLogger` calls `flush()` after every single write, producing approximately 190 synchronous disk commits per second. This causes significant I/O bottleneck that degrades game performance.

**Fix Required**: Buffer writes in memory and flush to disk every 1 second, except for error-level messages which must be flushed immediately.

**File**: `scripts/autoload/file_logger.gd`

## Root Cause Analysis

### The Problematic Code

In `scripts/autoload/file_logger.gd` (line 108–109), `_write_log()` calls `flush()` after every `store_line()`:

```gdscript
# (line 107-109 in original file_logger.gd)
if _log_file != null:
    _log_file.store_line(log_line)
    _log_file.flush()  # <-- called on EVERY write
```

### Why This Is Critical

`FileAccess.flush()` is a **synchronous disk commit**. It maps to `fflush()` on Linux/macOS and `FlushFileBuffers()` on Windows. Each call:

1. Forces the OS to write its internal I/O buffer to the hardware storage device.
2. May block the game thread until the OS acknowledges the write.
3. On SSDs: latency is typically 50–200 µs per flush. At 190/second, that's 9.5–38 ms/second of blocking I/O — meaning up to 3.8% of a 60 FPS frame budget can be consumed by logging alone.
4. On HDDs: latency is 5–15 ms per flush. At 190/second this would be catastrophic, potentially consuming many multiples of the entire frame budget.

### Why 190 Flushes/Second?

The issue states 190 synchronous disk commits/second. This originates from Godot's typical game loop at 60–120 FPS, multiplied by multiple log calls per frame (enemy AI state changes, weapon events, physics events, etc.). At 60 FPS with 3+ log calls per frame, this easily reaches 180–200 flushes/second.

### Reference: Godot FileAccess.flush()

- [FileAccess.flush() documentation](https://docs.godotengine.org/en/stable/classes/class_fileaccess.html#class-fileaccess-method-flush)
- [Related Godot issue #29075](https://github.com/godotengine/godot/issues/29075): Discusses the importance of explicit flushing for crash-safe log files, but notes it should not be called on every write.

## Current Implementation Analysis

### File: `scripts/autoload/file_logger.gd`

The logger is a `Node` autoload singleton with these key members:
- `_log_file: FileAccess` — the open file handle
- `_log_buffer: Array` — pre-file-open startup buffer (max 100 messages)
- `MAX_BUFFER_SIZE: int = 100` — limits startup buffer

The `_write_log(level, message)` method:
1. Formats: `[HH:MM:SS] [LEVEL] message`
2. Prints to console
3. If file open: `store_line()` + `flush()` ← **the problem**
4. If file not open yet: buffers to `_log_buffer`

### Existing Architecture Strengths
- Pre-file-open buffering is already implemented correctly.
- Proper teardown via `_notification()` with `NOTIFICATION_WM_CLOSE_REQUEST`.
- Logging can be disabled entirely via `set_logging_enabled(bool)` (Issue #848 feature).

## Solution Design

### Approach 1: Remove flush() entirely (not safe)

Simply delete the `flush()` call and rely on OS buffering.

- **Pros**: Zero overhead, trivially simple.
- **Cons**: On game crash, the last N seconds of logs may be lost entirely because the OS I/O buffer was never committed to disk. This defeats the primary purpose of a log file — which is crash debugging.

### Approach 2: Flush every N writes (not optimal)

Add a counter; flush every 100 writes.

- **Pros**: Simple, reduces flush frequency by 100×.
- **Cons**: Under bursty load (e.g., AI simulation: 200 writes in 0.1s), still flushes 2× in 0.1s. Under light load, may not flush for a very long time. No time-based guarantee.

### Approach 3: Time-based batch flush with a Timer node (chosen)

Add a `Timer` node child that fires every `FLUSH_INTERVAL` seconds (1.0s). On each timer tick, flush pending writes. Errors bypass buffering and flush immediately to prevent data loss on crash.

- **Pros**:
  - Reduces flushes from 190/second to 1/second (99.5% reduction).
  - Errors still flush immediately for crash-safety.
  - Time-based guarantee: at most 1 second of non-error logs can be lost.
  - Integrates naturally with Godot's node/process architecture.
- **Cons**:
  - Adds a `Timer` node to the scene tree — minor memory overhead.
  - Non-error logs may be lost if the game crashes mid-second.

### Chosen Implementation Plan

1. **Add `_flush_timer: Timer`** — a child Timer node, set to autostart, repeating, 1-second interval.
2. **Add `_write_buffer: Array[String]`** — collects formatted log lines between flushes.
3. **Modify `_write_log()`**: instead of `store_line()` + `flush()`, append to `_write_buffer`. For ERROR level, also call `_flush_write_buffer()` immediately.
4. **Add `_flush_write_buffer()`**: writes all lines from `_write_buffer` to `_log_file`, calls `flush()`, clears buffer.
5. **Connect Timer to `_flush_write_buffer()`** in `_ready()`.
6. **Call `_flush_write_buffer()` in `_close_log_file()`** to ensure all pending writes are committed on exit.
7. **Constant `FLUSH_INTERVAL: float = 1.0`** — configurable flush interval.

## Performance Impact

| Scenario | Before | After |
|---|---|---|
| 60 FPS, 3 log calls/frame | 180 flushes/sec | 1 flush/sec |
| 120 FPS, 3 log calls/frame | 360 flushes/sec | 1 flush/sec |
| Error burst (10 errors/sec) | 10 flushes/sec | 10 flushes/sec (unchanged) |
| Game shutdown | 1 final flush | 1 final flush |

Estimated CPU time saved: 95%+ of logging-related I/O overhead.

## References

- `scripts/autoload/file_logger.gd` — The file being modified
- `tests/unit/test_file_logger.gd` — Existing unit tests (MockFileLogger pattern)
- [Godot 4 FileAccess.flush()](https://docs.godotengine.org/en/stable/classes/class_fileaccess.html#class-fileaccess-method-flush)
- [Godot 4 Timer node](https://docs.godotengine.org/en/stable/classes/class_timer.html)
- [Godot issue #29075 — FileAccess flush discussion](https://github.com/godotengine/godot/issues/29075)
- [GDQuest optimization guide](https://www.gdquest.com/tutorial/godot/gdscript/optimization-code/)
- Related Issue #848 — Logging enable/disable feature (referenced in file_logger.gd comments)
