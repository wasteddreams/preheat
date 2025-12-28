# Startup Time Measurement - Revised Plan

## Overview
Track actual application startup times to measure preloading effectiveness.

---

## Design (Updated with Review Feedback)

### Core Data Structures

```c
/* In startup.c - Per-process tracker */
typedef struct {
    pid_t pid;
    char *exe_path;
    GTimeVal spawn_time;
    GTimeVal timeout_time;        /* Stop after 5s */
    gboolean was_preloaded;       /* Captured at spawn, immutable */
    int stable_count;             /* Cycles with no new maps */
    int map_count_last;           /* For detecting stabilization */
    gboolean timed_out;
} startup_tracker_t;

/* In state.h kp_exe_t - Per-app statistics */
#define STARTUP_SAMPLE_COUNT 10

double startup_samples_ms[STARTUP_SAMPLE_COUNT];  /* Rolling window */
int startup_sample_idx;
double startup_median_preloaded;   /* Median when preloaded */
double startup_median_cold;        /* Median when cold */
unsigned int preloaded_count;      /* Sample counts */
unsigned int cold_count;
```

### Stabilization Detection
"Stable" = no new executable/library mappings for 500ms:
```c
int current_map_count = count_executable_maps(pid);
if (current_map_count == tracker->map_count_last) {
    tracker->stable_count++;
} else {
    tracker->stable_count = 0;
    tracker->map_count_last = current_map_count;
}
// Stable when stable_count >= 5 (at 100ms intervals = 500ms)
```

### Cold Start Definition
Only mark as cold if:
1. Exe not currently preloaded
2. Exe not launched in last 5 minutes
3. System uptime > 60 seconds (avoid boot cache)

---

## Implementation

### Phase 1: Data Structures

#### [MODIFY] [state.h](file:///home/lostproxy/Documents/Experiment/kalipreload/include/state.h)
Add to `kp_exe_t`:
```c
/* Startup time measurement */
#define STARTUP_SAMPLE_COUNT 10
double startup_samples_ms[STARTUP_SAMPLE_COUNT];
int startup_sample_idx;
double startup_median_preloaded_ms;
double startup_median_cold_ms;
unsigned int startup_preloaded_count;
unsigned int startup_cold_count;
time_t last_launch_time;  /* For cold detection */
```

#### [MODIFY] [state_io.c](file:///home/lostproxy/Documents/Experiment/kalipreload/src/state/state_io.c)
Persist startup stats in state file.

---

### Phase 2: Startup Tracker Module

#### [NEW] src/monitor/startup.h
```c
void kp_startup_init(void);
void kp_startup_track(pid_t pid, const char *exe_path, gboolean was_preloaded);
void kp_startup_tick(void);  /* Called each 100ms */
void kp_startup_free(void);
```

#### [NEW] src/monitor/startup.c
- Max 5 concurrent trackers
- 5 second timeout per tracker
- Check maps every 100ms
- Record on stabilization or timeout
- Cleanup dead PIDs automatically

---

### Phase 3: Integration

#### [MODIFY] [spy.c](file:///home/lostproxy/Documents/Experiment/kalipreload/src/monitor/spy.c)
```c
/* When new process detected */
gboolean was_preloaded = exe && exe->is_preloaded;
exe->last_launch_time = time(NULL);  /* Update for cold detection */
kp_startup_track(pid, exe_path, was_preloaded);
```

#### [MODIFY] [state.c](file:///home/lostproxy/Documents/Experiment/kalipreload/src/state/state.c)
Add `kp_startup_tick()` to daemon tick cycle.

---

### Phase 4: Stats & CLI

#### [MODIFY] [stats.c](file:///home/lostproxy/Documents/Experiment/kalipreload/src/daemon/stats.c)
```c
double avg_speedup_percent;
int apps_with_speedup_data;
```

#### [MODIFY] [preheat-ctl.c](file:///home/lostproxy/Documents/Experiment/kalipreload/tools/preheat-ctl.c)
```
=== Startup Time Improvement ===
Average speedup: 34.2%
Apps measured: 12

Top improved apps:
  firefox    : 2.1s → 0.8s (62% faster) [n=8]
  code       : 1.5s → 0.9s (40% faster) [n=5]
  libreoffice: 3.2s → 2.1s (34% faster) [n=3]
```

---

## Error Handling

| Case | Handling |
|------|----------|
| Process exits during tracking | Detect via `/proc/PID` missing, cleanup tracker |
| Timeout (5s) | Record partial data, mark as timed out |
| Max trackers reached | Ignore new launches, log warning |
| Rapidly launched same app | Ignore duplicates (same exe_path within 1s) |

---

## Configuration

Add to `preheat.conf`:
```ini
[startup_timing]
enabled = true
stability_delay_ms = 500
max_tracking_time_ms = 5000
max_concurrent_tracks = 5
min_samples_for_display = 3
```

---

## Verification Plan

### Build & Basic
- Zero warnings
- Daemon starts without errors
- State file saves/loads startup data

### Functional
- Launch Firefox → timing logged
- Launch same app preloaded vs cold → different buckets
- `preheat-ctl stats --verbose` shows timing data

### Edge Cases
- Launch 10 apps rapidly → no crash, max 5 tracked
- Kill app during tracking → no memory leak
- App that forks (launches child) → parent tracked correctly
