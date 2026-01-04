# Hit/Miss Tracking Implementation Plan

> **Status:** ✅ Implemented (Dec 31, 2025)  
> **Priority:** Medium  
> **Estimated Effort:** 2-3 hours

## Problem

The daemon tracks preloads and launches but doesn't measure **effectiveness**:
- **Hit:** App was preloaded → user launched it (time saved!)
- **Miss:** App launched → wasn't preloaded (could have been faster)

Current stats show "N/A" for hits/misses, making it impossible to measure if preloading is actually helping.

## Observed Issues (Dec 31, 2025)

After 7+ hours of daemon runtime:
```
Preloads:            108 total
Hits:                0 (N/A)
Misses:              0 (N/A)
Total Preloaded:     3 MB    ← Suspiciously low!
Avg Size:            0 MB per app
```

**Concerns:**
1. Memory stats showing only 3 MB preloaded seems incorrect for 86 priority apps
2. Avg size 0 MB suggests the memory tracking isn't updating
3. May be related to readahead stats not being accumulated properly

---

## Design

### Core Concept

Track a sliding window of recently preloaded apps. When an app launches, check if it was preloaded within the window → Hit or Miss.

### Data Structures

```c
/* In state.h or stats.h */
typedef struct {
    GHashTable *preload_times;   /* path -> last_preload_timestamp */
    unsigned long hits;           /* Apps launched that were preloaded */
    unsigned long misses;         /* Apps launched that weren't preloaded */
    time_t window_seconds;        /* How long after preload counts as "warm" (default: 3600) */
} kp_hit_stats_t;
```

### Logic Flow

```
On Preload:
    preload_times[app_path] = current_time

On Launch Detection:
    if (app_path in preload_times):
        if (current_time - preload_times[app_path] < window_seconds):
            hits++
        else:
            misses++  // Preloaded too long ago, data evicted
    else:
        misses++  // Never preloaded
```

---

## Implementation

### Files to Modify

#### 1. `src/state/state.h`
Add hit stats to global state:
```c
extern kp_hit_stats_t kp_hit_stats;
```

#### 2. `src/readahead/readahead.c`
Record preload timestamp after successful readahead:
```c
void kp_readahead(kp_exe_t *exe) {
    // ... existing preload logic ...
    if (success) {
        g_hash_table_insert(kp_hit_stats.preload_times, 
                           g_strdup(exe->path), 
                           GINT_TO_POINTER(time(NULL)));
    }
}
```

#### 3. `src/monitor/spy.c`
Check for hit/miss when app launches:
```c
static void track_process_start(kp_exe_t *exe, pid_t pid, pid_t parent_pid) {
    // ... existing launch tracking ...
    
    /* Check hit/miss */
    gpointer preload_time = g_hash_table_lookup(kp_hit_stats.preload_times, exe->path);
    if (preload_time) {
        time_t elapsed = time(NULL) - GPOINTER_TO_INT(preload_time);
        if (elapsed < kp_hit_stats.window_seconds) {
            kp_hit_stats.hits++;
        } else {
            kp_hit_stats.misses++;
        }
    } else {
        kp_hit_stats.misses++;
    }
}
```

#### 4. `src/daemon/stats.c`
Add hits/misses to stats dump:
```c
g_message("hits: %lu, misses: %lu, hit_rate: %.1f%%",
          kp_hit_stats.hits, kp_hit_stats.misses,
          kp_hit_stats.hits * 100.0 / (kp_hit_stats.hits + kp_hit_stats.misses));
```

#### 5. `tools/ctl_cmd_stats.c`
Display in preheat-ctl stats output (already has N/A placeholders).

#### 6. `src/state/state_io.c`
Persist hits/misses across restarts (optional but recommended).

---

## Configuration

Add to `preheat.conf`:
```ini
[model]
# How long after preload is considered "warm" cache (seconds)
hitstats_window = 3600
```

---

## Testing

1. Start fresh daemon
2. Launch an app (should be Miss on first launch)
3. Wait for preload cycle
4. Launch same app again (should be Hit)
5. Check `preheat-ctl stats -v` shows accurate hit/miss counts

---

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| App preloaded but never launched | No effect on stats |
| App launched multiple times quickly | Each launch is counted |
| Daemon restart | Stats reset (unless persisted) |
| App in observation pool launched | Miss (not preloaded) |

---

## Future Enhancements

1. **Per-app hit rates** - Track which apps benefit most
2. **Time-of-day patterns** - Better prediction = higher hit rate
3. **Memory pressure correlation** - Lower hit rate when memory tight?
