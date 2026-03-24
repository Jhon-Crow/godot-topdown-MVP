# Godot 4.3 Threading and Export Crash Research

## Search Results Summary

### Search 1: Godot 4.3 mono export crash propagate_notification
- **Query**: "Godot 4.3 mono export crash "propagate_notification" "call_deferred" threading signal 11 2026"
- **Key Findings**:
  - Multiple reports of signal 11 crashes in Godot 4.3 related to threading issues
  - Error: "Caller thread can't call this function in this node" at `propagate_notification`
  - Crashes occur only during export, not when running from editor
  - Documented issue with `call_deferred` from thread during scene initialization
  - Regression introduced in 4.3 (did not occur in 4.2.1)

**Relevant Issues**:
- [Program crashed with signal 11. Godot 4.2.1 · Issue #88556](https://github.com/godotengine/godot/issues/88556)
- [Godot 4.1 crashes when opening projects · Issue #80899](https://github.com/godotengine/godot/issues/80899)
- [[4.2.1] Engine crashes on project load · Issue #86359](https://github.com/godotengine/godot/issues/86359)
- [Program crashed with signal 11 · Issue #100805](https://github.com/godotengine/godot/issues/100805)
- [Godot 4.3 Crashes During Import of Large Asset Directory · Issue #96242](https://github.com/godotengine/godot/issues/96242)
- [Deferred Calls Crash During Scene Initialization · Issue #106336](https://github.com/godotengine/godot/issues/106336)
- [4.3 Beta-1 Mono Unknown Crash · Issue #92615](https://github.com/godotengine/godot/issues/92615)

### Search 2: Caller thread error at node.cpp:2422
- **Query**: "Godot engine "Caller thread can't call this function" node.cpp 2422 mono export crash"
- **Key Findings**:
  - Known issue in Godot 4.2+ versions
  - Exact same error location: node.cpp:2422
  - Manifests when importing large directories of assets
  - Crash occurs in 4.3 and 4.2.2, but NOT in 4.2.1
  - Threading violation: function called from wrong thread

**Relevant Issues**:
- [ERROR: Caller thread can't call this function in this node (/root) · Issue #85687](https://github.com/godotengine/godot/issues/85687)
- [Crashing and error "Caller thread can't call this function" while using VS Code · Issue #83019](https://github.com/godotengine/godot/issues/83019)
- [ERROR: get_child_count: Caller thread can't call this function · Issue #78002](https://github.com/godotengine/godot/issues/78002)

### Search 3: dotnet publish crash with threading
- **Query**: "Godot 4.3 dotnet publish crash SIGSEGV threading scene tree"
- **Key Findings**:
  - C# non-main thread crashes when instantiating Node2D with UI/Control nodes
  - Works normally with empty Node2D or Sprite2D, but crashes with Label/Control
  - Multiple threads accessing same resource causes unexpected behaviors/crashes
  - Scene tree operations MUST happen on main thread

**Relevant Issues**:
- [Crash on PackedScene.Instantiate() C# Multithreading · Issue #83283](https://github.com/godotengine/godot/issues/83283)
- [[3.x] SIGSEGV Crash on Linux when using an external C# Library · Issue #49209](https://github.com/godotengine/godot/issues/49209)
- [Changes that should be inconsequential result in crashes and inconsistencies when a thread is involved · Issue #75873](https://github.com/godotengine/godot/issues/75873)
- [Crash when Thread Model is set to Multi-Threaded · Issue #61650](https://github.com/godotengine/godot/issues/61650)

## Critical Insights

1. **Godot 4.3 Regression**: Threading issues at node.cpp:2422 are a known regression in Godot 4.3
2. **Export-Specific**: Crashes often only occur during export, not in editor
3. **C# Mono Specific**: Issues are particularly prevalent in mono (C#) builds
4. **Large Scene Files**: Crashes correlate with large asset directories and large scene files
5. **Thread Safety**: Scene tree operations from non-main threads cause SIGSEGV crashes

