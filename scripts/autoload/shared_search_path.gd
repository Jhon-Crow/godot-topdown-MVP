extends Node
## SharedSearchPath - Search slot limiter for Issue #1458.
##
## Limits the number of enemies that can be in SEARCHING state simultaneously.
## Only MAX_SEARCHERS enemies search at a time; all others go to IDLE instead.
## Each searching enemy uses its own per-enemy spiral/predefined path logic,
## which works fine when limited to 1-2 searchers.

## Maximum simultaneous searchers. 2 keeps nav load minimal (2 nav queries/frame max).
const MAX_SEARCHERS: int = 2

## Set of currently active searcher instance IDs.
var _active: Dictionary = {}


## Try to acquire a search slot for this enemy.
## Returns true if slot granted (enemy may enter SEARCHING), false if full (go IDLE).
func try_acquire(enemy_id: int) -> bool:
	if _active.has(enemy_id):
		return true  # Already holds a slot (re-entering SEARCHING)
	if _active.size() >= MAX_SEARCHERS:
		FileLogger.log_info("[SharedSearchPath] Slot denied for %d (active=%d/%d)" % [enemy_id, _active.size(), MAX_SEARCHERS])
		return false
	_active[enemy_id] = true
	FileLogger.log_info("[SharedSearchPath] Slot granted for %d (active=%d/%d)" % [enemy_id, _active.size(), MAX_SEARCHERS])
	return true


## Release the search slot for this enemy. Safe to call even if not holding a slot.
func release(enemy_id: int) -> void:
	if _active.erase(enemy_id):
		FileLogger.log_info("[SharedSearchPath] Slot released for %d (active=%d/%d)" % [enemy_id, _active.size(), MAX_SEARCHERS])


## Returns the number of currently active searchers.
func get_active_count() -> int:
	return _active.size()


## Returns whether a slot is currently held by this enemy.
func is_active(enemy_id: int) -> bool:
	return _active.has(enemy_id)
