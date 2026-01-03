# Snap Firefox Detection & Tracking

**Status:** Resolved ✅  
**Date Resolved:** December 31, 2025  
**Affected Systems:** Ubuntu 22.04+, Kali Linux (with snap)

---

## Executive Summary

Firefox installed via snap was failing to be properly tracked by the preheat daemon. After extensive debugging across both Kali Linux and Ubuntu 24.04, two distinct root causes were identified and fixed:

| System | Root Cause | Fix |
|--------|-----------|-----|
| **Kali Linux** | AppArmor blocks `/proc/PID/maps` access | cmdline fallback in `proc.c` |
| **Ubuntu 24.04** | Desktop file scanner path mismatch | Path resolution fixes in `desktop.c` |

---

## Problem Statement

Users reported Firefox not appearing in `preheat-ctl stats` despite daily usage:
- `preheat-ctl explain /snap/firefox/.../firefox` showed "NOT TRACKED"
- Other apps (23+) tracked successfully
- Some classic snaps worked, strictly-confined ones did not

---

## Root Cause Analysis

### Issue 1: AppArmor Blocking (Kali)

Snap's AppArmor profile blocks external processes from reading `/proc/PID/maps` for confined processes:

```bash
$ sudo cat /proc/$(pgrep firefox)/maps
# Permission denied even as root!
```

This caused `kp_proc_get_maps()` to return 0, triggering silent exit in `new_exe_callback()`.

### Issue 2: Desktop File Scanner (Ubuntu)

On Ubuntu, `/proc` access works, but the desktop file scanner couldn't match snap paths:

1. **Missing scan directory:** Snap `.desktop` files are in `/var/lib/snapd/desktop/applications/`, not standard XDG locations
2. **Exec= prefix:** Snap uses `Exec=env BAMF_DESKTOP_FILE_HINT=... /snap/bin/firefox`
3. **Symlink resolution:** `/snap/bin/firefox` → `/usr/bin/snap` (not the actual binary). `realpath()` broke detection

---

## Fixes Implemented

### proc.c: cmdline Fallback for EACCES

```c
if (err == EACCES || err == EPERM) {
    /* Fallback: read /proc/PID/cmdline for snap apps */
    char cmdline_path[64];
    g_snprintf(cmdline_path, sizeof(cmdline_path), "/proc/%s/cmdline", entry->d_name);
    // ... extract first argument (exe path)
    if (exe_buffer[0] == '/') goto process_exe;
}
```

### desktop.c: Snap Path Resolution

```c
// 1. Scan snap desktop directory
scan_desktop_dir("/var/lib/snapd/desktop/applications");

// 2. Skip env VAR=value prefixes
if (strcmp(binary, "env") == 0) {
    while (argv[i] && strchr(argv[i], '=')) i++;
    binary = argv[i];
}

// 3. Resolve snap wrappers BEFORE realpath()
if (g_str_has_prefix(path, "/snap/bin/")) {
    return resolve_snap_binary(path);  // /snap/<name>/current/usr/lib/<name>/<name>
}
```

### spy.c: Desktop Fallback for Launch Counting

```c
/* For snap/flatpak: if exe has .desktop file, treat as user-initiated */
if (!proc_info->user_initiated && kp_desktop_has_file(exe->path)) {
    proc_info->user_initiated = TRUE;
}
```

### config: Added /snap/ to exeprefix

```ini
exeprefix_raw = /usr/;/bin/;/opt/;/snap/
```

---

## Test Results

**Before fix:**
```
Desktop scanner initialized: discovered 38 GUI applications
Reclassified /snap/firefox/6565/usr/lib/firefox/firefox: priority → observation (reason: default (no match))
```

**After fix:**
```
Desktop scanner initialized: discovered 43 GUI applications
Reclassified /snap/firefox/6565/usr/lib/firefox/firefox: observation → priority (reason: .desktop (Firefox))

Pool Classification: ✓ PASS (priority pool)
Launch Tracking: ✓ PASS (1 launches recorded)
```

---

## Distro Differences

| Behavior | Kali Linux | Ubuntu 24.04 |
|----------|------------|--------------|
| `/proc/PID/maps` access | Blocked by AppArmor | Allowed for root |
| `/proc/PID/exe` access | Blocked | Allowed |
| Desktop file location | Standard XDG | `/var/lib/snapd/desktop/applications/` |
| Exec= format | Standard | Uses `env BAMF_DESKTOP_FILE_HINT=...` |
| `/snap/bin/X` | Symlink to `/usr/bin/snap` | Same |

---

## Known Limitations

1. **Strictly-confined snaps on Kali:** May not track libraries (only main binary preloaded)
2. **Persistent helper processes:** Some snap apps maintain background PIDs, causing launch counter to under-report
3. **Docker/Firejail:** Similar sandboxing issues apply

**Workarounds:**
- Install Firefox via apt instead of snap
- Use Flatpak (less restrictive sandboxing)

---

## Files Modified

| File | Change |
|------|--------|
| `src/monitor/proc.c` | cmdline fallback for EACCES |
| `src/utils/desktop.c` | Snap path resolution, env prefix handling |
| `src/monitor/spy.c` | Desktop file fallback for launch counting |
| `config/preheat.conf.default` | Added `/snap/` to exeprefix |
| `docs/known-limitations.md` | Documented snap limitations |

---

## Commits

1. `feat: fallback to cmdline when exe blocked by snap sandbox`
2. `feat: resolve snap wrapper scripts to actual binaries in desktop.c`
3. `fix: scan /var/lib/snapd/desktop/applications for snap .desktop files`
4. `fix: skip 'env VAR=value' prefixes in Exec= lines`
5. `fix: check snap wrapper BEFORE realpath() to prevent resolution to /usr/bin/snap`
6. `fix: add desktop file fallback for snap/container launch counting`

---

## How to Verify

```bash
# On Ubuntu with snap Firefox
sudo systemctl restart preheat
sleep 100  # Wait for scan cycle

# Verify Firefox is in priority pool
preheat-ctl explain /snap/firefox/*/usr/lib/firefox/firefox
# Expected: Pool: priority
```

---

## Debug Timeline

### Phase 1: Initial Discovery (Dec 28)
- Firefox not in `preheat-ctl stats` on Ubuntu
- `exeprefix` config didn't include `/snap/`

### Phase 2: Config Fix
- Added `/snap/` to prefixes
- Fixed config parsing (semicolons vs commas)

### Phase 3: Permission Discovery
- Found AppArmor blocking `/proc/PID/exe` on Kali
- Implemented cmdline fallback

### Phase 4: Still Not Working
- Firefox passed all proc.c filters but not in state
- Silent drop somewhere in spy.c

### Phase 5: Ubuntu VM Testing (Dec 31)
- Discovered AppArmor NOT blocking on Ubuntu
- Found desktop.c was the real issue

### Phase 6: Resolution
- Implemented 4 desktop.c fixes
- Firefox now in priority pool on both systems
