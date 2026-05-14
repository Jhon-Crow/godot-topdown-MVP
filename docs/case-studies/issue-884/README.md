# Issue #884 Case Study: HIGH — Sound Propagation Processes 22% No-Op Events

## Issue Description

**Title**: оптимизируй HIGH: Sound Propagation Processes 22% No-Op Events

**Severity**: HIGH

**Summary**: `SoundPropagation.emit_sound()` processed 6,437 out of 29,095 sound events (22.1%) as
no-ops — the listener array was empty, yet the function still performed array filtering, counter
variable initialization, a full loop, and file logging. The fix is a single early-exit guard.

**File**: `scripts/autoload/sound_propagation.gd`, line 150

---

## Timeline / Sequence of Events

```
29,095 emit_sound() calls total (observed during a gameplay session)
 └─ 22,658 calls (77.9%) — listeners present, normal propagation
 └─  6,437 calls (22.1%) — _listeners array empty, full body executed anyway
       ├── _listeners.filter(...)     ← allocates new array (GC pressure)
       ├── 4 counter vars initialized ← minor but unnecessary
       ├── for-loop entered           ← iterates 0 items
       └── _log_to_file(result: ...) ← disk I/O for zero-notification events
```

The 22% empty-listener rate is expected during game startup and scene transitions, when enemies
haven't yet called `register_listener()` but the player can already fire weapons.

---

## Root Cause Analysis

### Affected Code (Before Fix)

In `scripts/autoload/sound_propagation.gd`, the `emit_sound()` function had no guard before its
expensive body:

```gdscript
# Line 150 — executed even when _listeners is empty
# Clean up invalid listeners (destroyed nodes)
var prev_count := _listeners.size()
_listeners = _listeners.filter(func(l): return is_instance_valid(l))
if _listeners.size() < prev_count:
    _log_to_file("Cleaned up %d invalid listeners" % ...)

# Notify all listeners within range
var listeners_notified := 0
var listeners_out_of_range := 0
var listeners_skipped_self := 0
var listeners_below_threshold := 0

for listener: Node2D in _listeners:   # ← iterates 0 elements, still allocated
    ...

_log_to_file("Sound result: notified=0, out_of_range=0, ...")  # ← disk write for nothing
```

### Why Empty Listeners Happen

- **Game startup**: Autoloads initialize before enemies are added to the scene; the player can
  fire (triggering `emit_sound`) before any enemy calls `register_listener`.
- **Scene transitions**: When loading a new level, all enemies are freed (triggering
  `unregister_listener`), but weapon systems continue to fire for a few frames.
- **Low-enemy rooms**: Some rooms have no enemies; any sound there produces a no-op call chain.

### Cost of Each No-Op Call

| Operation | Cost |
|---|---|
| `_listeners.filter(lambda)` | Allocates a new Array, runs lambda 0 times — still has GC overhead |
| 4 counter variable initializations | Negligible individually, but wasted in aggregate |
| `for listener in _listeners` | Loop setup overhead for 0 iterations |
| `_log_to_file("Sound result: ...")` | Synchronous-buffered write (see Issue #885), still work |

At 22% of 29,095 calls = **6,437 unnecessary filter+loop+log cycles per session**.

---

## Fix

A single early-exit guard was added immediately before the expensive operations:

```gdscript
# Early exit when no listeners are registered — avoids filter, loop, and logging overhead
if _listeners.is_empty():
    return
```

### After Fix

```
29,095 emit_sound() calls total
 └─ 22,658 calls (77.9%) — listeners present, full propagation logic runs
 └─  6,437 calls (22.1%) — listeners empty, returns immediately after initial debug log
       ├── _listeners.is_empty() → true → return  ← O(1), no allocation
       └── (all remaining body skipped)
```

### Performance Impact

| Metric | Before | After |
|---|---|---|
| No-op calls executing filter | 6,437 | 0 |
| No-op calls executing loop | 6,437 | 0 |
| No-op calls writing to file logger | 6,437 | 0 |
| Array allocations from no-op filter | 6,437 | 0 |
| Code change size | — | +3 lines |

---

## Solution Design

The fix is minimal and surgical:
- Placed **after** the initial debug log (so diagnostics still capture the sound emission event)
- Placed **before** `_listeners.filter(...)` (the first expensive operation)
- Uses `Array.is_empty()` which is O(1) — checking the internal size counter, no iteration

This matches the pattern used in the similar Issue #885 fix (batching FileLogger flushes) — do the
minimum necessary to avoid wasted work, without restructuring or complicating the existing logic.

---

## Additional Facts and References

- **Godot Array.filter()**: Creates a new Array and invokes the lambda for every element. Even
  with 0 elements, the method call itself involves object allocation overhead in GDScript.
  Source: [Godot docs — Array.filter()](https://docs.godotengine.org/en/stable/classes/class_array.html#class-array-method-filter)

- **22% no-op rate context**: A 22% wasted-call rate is significant in a hot path. The
  `emit_sound()` function is called on every weapon fire, grenade throw, footstep, reload, and
  shell casing event. At 60 FPS with frequent player actions, this accumulates quickly.

- **Comparable optimization pattern**: Issue #885 applied the same principle to `FileLogger`
  (skip the flush when the buffer is empty). Both cases follow the "fail fast / exit early"
  optimization pattern, well-established in performance-sensitive code:
  > "The cheapest operation is the one you don't do." — common systems programming principle

- **GDScript GC pressure**: In Godot 4, GDScript uses reference counting. Each `Array.filter()`
  allocates a new `Array` object that must be reference-counted and eventually collected. At
  6,437 unnecessary allocations per session, this adds measurable GC pressure on top of the
  CPU cost.

---

## Files Changed

| File | Change |
|---|---|
| `scripts/autoload/sound_propagation.gd` | Added 3-line early exit guard in `emit_sound()` |
| `tests/unit/test_sound_propagation.gd` | Added `test_emit_sound_with_no_listeners_does_not_crash()` |
| `docs/case-studies/issue-884/README.md` | This document |

---

## Proposed Solutions (Evaluated)

### Option A: Early exit when `_listeners` is empty ✅ (chosen)
**Pros**: Minimal change, zero risk of regression, O(1) guard, no restructuring needed.
**Cons**: None — the initial debug log still fires so diagnostics are unaffected.

### Option B: Move filter before the log and early-exit after filter
**Pros**: Would also clean up invalid listeners before the early exit.
**Cons**: Slightly more complex, and invalid listeners are already cleaned up on the next
non-empty call. Not necessary for correctness.

### Option C: Cache filtered listener count in a variable
**Pros**: Avoids re-filtering on every call.
**Cons**: Over-engineering for this issue; the filter is needed for correctness (destroyed nodes).

**Chosen**: Option A — minimal, targeted, no risk.
