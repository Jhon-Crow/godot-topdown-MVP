# Log Analysis: Issue #330 - Enemy Search Behavior

## Log Files Analyzed

| File | Lines | Size | Description |
|------|-------|------|-------------|
| `game_log_20260125_002728.txt` | 15,368 | 1.3 MB | Long gameplay session |
| `game_log_20260125_003509.txt` | 3,957 | 343 KB | Medium session |
| `game_log_20260125_004546.txt` | 258 | 22 KB | Short session |

## Key Findings

### Finding 1: Enemies Search the Same Center Point

When multiple enemies enter SEARCHING state (triggered by Last Chance effect), they all target the **same center coordinates**:

```
[00:34:07] [Enemy2] Search mode: SUPPRESSED -> SEARCHING at (1464.378, 406.5967)
[00:34:07] [Enemy2] SEARCHING started: center=(1464.378, 406.5967), radius=100, waypoints=5
[00:34:07] [Enemy4] Search mode: FLANKING -> SEARCHING at (1464.378, 406.5967)
[00:34:07] [Enemy4] SEARCHING started: center=(1464.378, 406.5967), radius=100, waypoints=5
[00:34:07] [Enemy5] Search mode: COMBAT -> SEARCHING at (1464.378, 379.0967)
[00:34:07] [Enemy5] SEARCHING started: center=(1464.378, 379.0967), radius=100, waypoints=5
[00:34:07] [Enemy9] Search mode: COMBAT -> SEARCHING at (1464.378, 379.0967)
[00:34:07] [Enemy9] SEARCHING started: center=(1464.378, 379.0967), radius=100, waypoints=5
```

**Observation:** All 4 enemies start with:
- Same X coordinate: 1464.378
- Very similar Y coordinates: 406.5967 and 379.0967 (only ~27px difference)
- Same initial radius: 100
- Same waypoint count: 5

**Impact:** This causes enemies to cluster together since they're all following nearly identical search patterns.

### Finding 2: Synchronized Radius Expansion

Enemies expand their search radius almost simultaneously:

```
[00:34:13] [Enemy5] SEARCHING: Expand outer ring r=175 wps=4
[00:34:13] [Enemy9] SEARCHING: Expand outer ring r=175 wps=4
[00:34:14] [Enemy2] SEARCHING: Expand outer ring r=175 wps=4
[00:34:16] [Enemy4] SEARCHING: Expand outer ring r=175 wps=4
```

Then again:
```
[00:34:21] [Enemy5] SEARCHING: Expand outer ring r=250 wps=4
[00:34:21] [Enemy9] SEARCHING: Expand outer ring r=250 wps=4
[00:34:22] [Enemy2] SEARCHING: Expand outer ring r=250 wps=4
[00:34:24] [Enemy4] SEARCHING: Expand outer ring r=250 wps=4
```

**Pattern:** Expansions happen within 1-3 seconds of each other because enemies:
1. Start at the same time
2. Move at the same speed
3. Have the same number of waypoints
4. Experience similar navigation conditions

### Finding 3: Consistent 30-Second Timeout

All enemies timeout after exactly 30 seconds:

```
[00:34:37] [Enemy2] SEARCHING timeout after 30.0s, returning to IDLE
[00:34:37] [Enemy4] SEARCHING timeout after 30.0s, returning to IDLE
[00:34:37] [Enemy5] SEARCHING timeout after 30.0s, returning to IDLE
[00:34:37] [Enemy9] SEARCHING timeout after 30.0s, returning to IDLE
```

**Timeline Analysis:**
- Search started: 00:34:07
- Timeout: 00:34:37
- Duration: Exactly 30.0 seconds

**Problem:** This represents `SEARCH_MAX_DURATION = 30.0` constant being too short for finding a hidden player, especially after combat contact.

### Finding 4: Player Detection Interrupts Search

When an enemy spots the player during search, it properly transitions to COMBAT:

```
[00:35:51] [Enemy1] SEARCHING: Player spotted! Transitioning to COMBAT
[00:35:51] [Enemy1] State: SEARCHING -> COMBAT
[00:35:51] [Enemy10] SEARCHING: Player spotted! Transitioning to COMBAT
[00:35:51] [Enemy10] State: SEARCHING -> COMBAT
```

**This works correctly** - the SEARCHING state properly checks `_can_see_player` and transitions accordingly.

### Finding 5: State Transitions Before Search

Enemies enter SEARCHING from various states:

| From State | Occurrences | Example |
|------------|-------------|---------|
| SUPPRESSED | 6 | Enemy1, Enemy2, Enemy4 |
| COMBAT | 4 | Enemy5, Enemy9 |
| FLANKING | 2 | Enemy4, Enemy10 |
| RETREATING | 2 | Enemy2, Enemy3 |
| PURSUING | 2 | Enemy1, Enemy10 |
| IDLE | 2 | Enemy5, Enemy7 |

**Implication:** The memory reset (Last Chance effect) correctly triggers SEARCHING from multiple states, as designed.

### Finding 6: Multiple Search Sessions

The same enemies enter SEARCHING multiple times during gameplay:

**Session 1 (00:34:07):**
```
Enemy2, Enemy4, Enemy5, Enemy9 -> SEARCHING
All timeout at 00:34:37 -> IDLE
```

**Session 2 (00:35:23):**
```
Enemy1, Enemy2, Enemy3, Enemy4, Enemy10 -> SEARCHING
Enemy1, Enemy10 spot player at 00:35:51 -> COMBAT
Rest timeout at 00:35:53 -> IDLE
```

**Session 3 (00:36:13):**
```
7 enemies enter SEARCHING
All timeout at 00:36:43 -> IDLE
```

**Observation:** Player successfully triggers Last Chance multiple times. The search pattern repeats the same issues each time:
- Enemies cluster at same location
- All expand simultaneously
- All timeout together

## Quantitative Analysis

### Waypoint Generation

Initial waypoints: 5
After expansions:
- r=175: 4 waypoints (skipping visited zones)
- r=250: 4 waypoints
- r=325: 4 waypoints (just before timeout)

Total waypoints per enemy per session: ~17

### Search Coverage

With 4 enemies all searching the same area:
- Duplicated coverage: ~75%
- Unique coverage: ~25% (slightly different Y offsets)

**Optimal:** With proper coordination, 4 enemies could cover 4x the area in the same time.

### Time Analysis

| Event | Time | Duration |
|-------|------|----------|
| Search start | 00:00:00 | - |
| First expansion (r=175) | 00:00:06 | 6s |
| Second expansion (r=250) | 00:00:14 | 8s |
| Third expansion (r=325) | 00:00:23 | 9s |
| Timeout | 00:00:30 | 7s |

**Note:** Expansion intervals increase as outer rings have more waypoints to visit.

## Recommendations from Log Analysis

### 1. Implement Global Waypoint Deconfliction

Before assigning a waypoint to an enemy, check if another enemy is already assigned to search that zone.

### 2. Stagger Search Start Times

Add a small random delay (0.5-1.5s) before each enemy starts searching to prevent synchronized movement.

### 3. Offset Search Centers

Assign each enemy a unique search center offset from the last known position:
- Enemy 1: center + (100, 0)
- Enemy 2: center + (-100, 0)
- Enemy 3: center + (0, 100)
- Enemy 4: center + (0, -100)

### 4. Extend or Remove Timeout After Contact

For enemies that have engaged the player (had `_can_see_player == true` at some point), extend or eliminate the search timeout:
- No contact: 30s timeout (patrol enemy investigating sound)
- Had contact: No timeout until max radius (engaged enemy hunting)

### 5. Share Visited Zones Globally

Make `_search_visited_zones` a global dictionary so enemies don't re-search areas already cleared by allies.

## Raw Log Excerpts

### Complete Search Session Example

```
[00:36:13] [ENEMY] [Enemy1] Search mode: PURSUING -> SEARCHING at (856.6814, 730.0182)
[00:36:13] [ENEMY] [Enemy1] SEARCHING started: center=(856.6814, 730.0182), radius=100, waypoints=5
[00:36:13] [ENEMY] [Enemy2] Search mode: COMBAT -> SEARCHING at (758.5001, 727.0147)
[00:36:13] [ENEMY] [Enemy2] SEARCHING started: center=(758.5001, 727.0147), radius=100, waypoints=5
[00:36:13] [ENEMY] [Enemy3] Search mode: SUPPRESSED -> SEARCHING at (856.6814, 730.0182)
[00:36:13] [ENEMY] [Enemy3] SEARCHING started: center=(856.6814, 730.0182), radius=100, waypoints=5
[00:36:13] [ENEMY] [Enemy4] Search mode: SUPPRESSED -> SEARCHING at (856.6814, 730.0182)
[00:36:13] [ENEMY] [Enemy4] SEARCHING started: center=(856.6814, 730.0182), radius=100, waypoints=5
[00:36:13] [ENEMY] [Enemy5] Search mode: IDLE -> SEARCHING at (743.0773, 744.3192)
[00:36:13] [ENEMY] [Enemy5] SEARCHING started: center=(743.0773, 744.3192), radius=100, waypoints=5
[00:36:13] [ENEMY] [Enemy7] Search mode: IDLE -> SEARCHING at (743.0773, 744.3192)
[00:36:13] [ENEMY] [Enemy7] SEARCHING started: center=(743.0773, 744.3192), radius=100, waypoints=5
[00:36:13] [ENEMY] [Enemy10] Search mode: FLANKING -> SEARCHING at (743.0773, 744.3192)
[00:36:13] [ENEMY] [Enemy10] SEARCHING started: center=(743.0773, 744.3192), radius=100, waypoints=5

[00:36:21] [ENEMY] [Enemy2] SEARCHING: Expand outer ring r=175 wps=4
[00:36:24] [ENEMY] [Enemy5] SEARCHING: Expand outer ring r=175 wps=4
[00:36:24] [ENEMY] [Enemy7] SEARCHING: Expand outer ring r=175 wps=4
[00:36:24] [ENEMY] [Enemy10] SEARCHING: Expand outer ring r=175 wps=4
[00:36:26] [ENEMY] [Enemy4] SEARCHING: Expand outer ring r=175 wps=4
[00:36:26] [ENEMY] [Enemy3] SEARCHING: Expand outer ring r=175 wps=4
[00:36:26] [ENEMY] [Enemy1] SEARCHING: Expand outer ring r=175 wps=4

[00:36:27] [ENEMY] [Enemy2] SEARCHING: Expand outer ring r=250 wps=4
[00:36:30] [ENEMY] [Enemy5] SEARCHING: Expand outer ring r=250 wps=4
[00:36:31] [ENEMY] [Enemy7] SEARCHING: Expand outer ring r=250 wps=4
[00:36:31] [ENEMY] [Enemy10] SEARCHING: Expand outer ring r=250 wps=4
[00:36:38] [ENEMY] [Enemy4] SEARCHING: Expand outer ring r=250 wps=4
[00:36:38] [ENEMY] [Enemy3] SEARCHING: Expand outer ring r=250 wps=4
[00:36:39] [ENEMY] [Enemy1] SEARCHING: Expand outer ring r=250 wps=4

[00:36:41] [ENEMY] [Enemy2] SEARCHING: Expand outer ring r=325 wps=4
[00:36:43] [ENEMY] [Enemy1] SEARCHING timeout after 30.0s, returning to IDLE
[00:36:43] [ENEMY] [Enemy2] SEARCHING timeout after 30.0s, returning to IDLE
[00:36:43] [ENEMY] [Enemy3] SEARCHING timeout after 30.0s, returning to IDLE
[00:36:43] [ENEMY] [Enemy4] SEARCHING timeout after 30.0s, returning to IDLE
[00:36:43] [ENEMY] [Enemy5] SEARCHING timeout after 30.0s, returning to IDLE
[00:36:43] [ENEMY] [Enemy7] SEARCHING timeout after 30.0s, returning to IDLE
[00:36:43] [ENEMY] [Enemy10] SEARCHING timeout after 30.0s, returning to IDLE
```

**Key observations from this session:**
1. 7 enemies enter SEARCHING at essentially the same time
2. Centers cluster into 3 groups:
   - (856.6814, 730.0182): Enemy1, Enemy3, Enemy4
   - (758.5001, 727.0147): Enemy2
   - (743.0773, 744.3192): Enemy5, Enemy7, Enemy10
3. All expand synchronously
4. All timeout simultaneously at 00:36:43
