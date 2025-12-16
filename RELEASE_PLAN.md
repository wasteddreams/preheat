# Preheat Production Release Plan

**Version:** 1.0  
**Target:** Kali Linux / Debian-based distributions  
**Status:** EXECUTABLE

---

## Dependency Map

```
PHASE 0 ──► PHASE 1 ──► PHASE 2 ──► PHASE 3 ──► PHASE 4
                                        │
                                        ▼
PHASE 5 ◄────────────────────────── PHASE 4
    │
    ▼
PHASE 6 ──► PHASE 7 ──► PHASE 8 ──► PHASE 9 (GO/NO-GO)
```

**Parallel Tracks:**
- Phase 7 (Docs) can run parallel to Phase 6 (Packaging)
- Phase 8 (Repo Hygiene) can begin during Phase 7

---

## Phase 0: Baseline Audit & Scope Lock

**Objective:** Establish known-good baseline; freeze scope for release.

### Entry Criteria
- Repository exists with buildable code
- No active development branches with unmerged critical changes

### Tasks
| # | Task | Priority | Status |
|---|------|----------|--------|
| 0.1 | Verify clean build with no errors | P0 | ☐ |
| 0.2 | Verify all tests pass | P0 | ☐ |
| 0.3 | Lock feature scope (no new features) | P0 | ☐ |
| 0.4 | Document current version in configure.ac | P1 | ☐ |
| 0.5 | Create project_status.md | P0 | ☐ |

### Exit Criteria
- `make clean && make` succeeds with no errors
- `make check` passes (or tests directory clean)
- `project_status.md` exists and is populated
- Version string is set (0.1.0)

**Blockers:** Build failures, missing dependencies  
**Effort:** Low  
**Ship this phase?** NO — Baseline only, no verification yet.

---

## Phase 1: Behavioral Parity & Core Safety (NON-NEGOTIABLE)

**Objective:** Verify daemon behavior matches upstream preload 0.6.4 defaults.

### Entry Criteria
- Phase 0 complete
- Clean build available

### Tasks
| # | Task | Priority | Status |
|---|------|----------|--------|
| 1.1 | Verify default config values match upstream | P0 | ☐ |
| 1.2 | Verify prediction algorithm unchanged | P0 | ☐ |
| 1.3 | Verify readahead() call semantics | P0 | ☐ |
| 1.4 | Verify /proc scanning matches upstream | P0 | ☐ |
| 1.5 | Verify Markov chain math is identical | P0 | ☐ |
| 1.6 | Verify memory budget calculation | P0 | ☐ |

### Exit Criteria
- All `confkeys.h` defaults match preload 0.6.4
- Code review confirms algorithm parity
- No behavioral changes from upstream

**Blockers:** Any deviation from upstream defaults  
**Effort:** Medium  
**Ship this phase?** NO — Safety verified, not runtime tested.

> ⚠️ **ROLLBACK POINT:** If any behavioral deviation found, STOP and fix before proceeding.

---

## Phase 2: Runtime & Signal Verification

**Objective:** Verify daemon operates correctly in real systemd environment.

### Entry Criteria
- Phase 1 complete
- Daemon installed on test system

### Tasks
| # | Task | Priority | Status |
|---|------|----------|--------|
| 2.1 | Verify daemon starts via systemd | P0 | ☐ |
| 2.2 | Verify daemon stops gracefully (SIGTERM) | P0 | ☐ |
| 2.3 | Verify SIGHUP reloads config | P0 | ☐ |
| 2.4 | Verify SIGUSR1 dumps state to log | P1 | ☐ |
| 2.5 | Verify SIGUSR2 saves state immediately | P1 | ☐ |
| 2.6 | Verify PID file creation/removal | P1 | ☐ |
| 2.7 | Verify nice level applied | P2 | ☐ |
| 2.8 | Verify foreground mode (-f) works | P2 | ☐ |

### Exit Criteria
- All signals produce expected behavior
- Daemon survives 1-hour runtime without crash
- systemctl start/stop/restart all work

**Blockers:** Signal handling failures, systemd integration issues  
**Effort:** Medium  
**Ship this phase?** NO — Need state file verification.

---

## Phase 3: State File Integrity & Persistence Safety

**Objective:** Verify state file survives restarts and is not corrupted.

### Entry Criteria
- Phase 2 complete
- Daemon has run for at least 1 hour

### Tasks
| # | Task | Priority | Status |
|---|------|----------|--------|
| 3.1 | Verify state file created after first run | P0 | ☐ |
| 3.2 | Verify state file survives daemon restart | P0 | ☐ |
| 3.3 | Verify state file survives system reboot | P0 | ☐ |
| 3.4 | Verify corrupted state file handled gracefully | P0 | ☐ |
| 3.5 | Verify missing state file handled gracefully | P0 | ☐ |
| 3.6 | Verify state file permissions (0600) | P1 | ☐ |
| 3.7 | Verify autosave interval works | P2 | ☐ |

### Exit Criteria
- State file persists across multiple restarts
- Daemon starts cleanly with missing/corrupt state
- No data loss during normal operation

**Blockers:** State file corruption, permission issues  
**Effort:** Medium  
**Ship this phase?** NO — Need failure mode testing.

---

## Phase 4: Failure Modes & Degraded Operation

**Objective:** Verify daemon fails safely under adverse conditions.

### Entry Criteria
- Phase 3 complete

### Tasks
| # | Task | Priority | Status |
|---|------|----------|--------|
| 4.1 | Verify behavior with read-only /proc | P0 | ☐ |
| 4.2 | Verify behavior with full disk | P1 | ☐ |
| 4.3 | Verify behavior with very low memory | P1 | ☐ |
| 4.4 | Verify behavior when config file missing | P1 | ☐ |
| 4.5 | Verify behavior when log directory missing | P1 | ☐ |
| 4.6 | Verify OOM killer interaction | P2 | ☐ |
| 4.7 | Verify behavior under rapid SIGHUP flood | P2 | ☐ |

### Exit Criteria
- Daemon never crashes on expected failure conditions
- Error messages are logged, not silent
- Graceful degradation, not undefined behavior

**Blockers:** Crash on failure condition  
**Effort:** Medium  
**Ship this phase?** YES (with Phase 5) — Core functionality verified.

---

## Phase 5: Security & Abuse Surface Review

**Objective:** Verify no exploitable vulnerabilities in deployment configuration.

### Entry Criteria
- Phase 4 complete

### Tasks
| # | Task | Priority | Status |
|---|------|----------|--------|
| 5.1 | Verify systemd hardening directives applied | P0 | ☐ |
| 5.2 | Verify file permissions on all installed files | P0 | ☐ |
| 5.3 | Verify state file permissions (0600) | P0 | ☐ |
| 5.4 | Verify no symlink attack surface | P1 | ☐ |
| 5.5 | Verify PID file race condition documented | P1 | ☐ |
| 5.6 | Verify build uses security flags (PIE, RELRO) | P1 | ☐ |
| 5.7 | Audit completed and findings addressed | P0 | ☐ |

### Exit Criteria
- `systemd-analyze security preheat.service` score < 7.0
- All P0 security findings resolved
- Security audit report exists

**Blockers:** Unresolved P0 security findings  
**Effort:** Low (already done)  
**Ship this phase?** YES — Security-hardened.

> ⚠️ **ROLLBACK POINT:** If new security issues found, return to Phase 5.

---

## Phase 6: Packaging & Distribution Readiness

**Objective:** Verify installation and uninstallation work correctly.

### Entry Criteria
- Phase 5 complete

### Tasks
| # | Task | Priority | Status |
|---|------|----------|--------|
| 6.1 | Verify `make install` installs all files | P0 | ☐ |
| 6.2 | Verify `make uninstall` removes all files | P0 | ☐ |
| 6.3 | Verify man pages installed and accessible | P0 | ☐ |
| 6.4 | Verify config file installed with defaults | P0 | ☐ |
| 6.5 | Verify systemd service installed correctly | P0 | ☐ |
| 6.6 | Verify install script works end-to-end | P1 | ☐ |
| 6.7 | Verify upgrade path (old→new) works | P2 | ☐ |

### Exit Criteria
- Fresh install on clean system succeeds
- `man preheat` works after install
- Uninstall leaves no orphan files

**Blockers:** Missing install targets, orphan files  
**Effort:** Low  
**Parallel:** Can run with Phase 7  
**Ship this phase?** YES — Installable.

---

## Phase 7: Documentation & Man Page Verification

**Objective:** Verify all documentation is accurate and complete.

### Entry Criteria
- Phase 5 complete

### Tasks
| # | Task | Priority | Status |
|---|------|----------|--------|
| 7.1 | Verify README.md is accurate | P0 | ☐ |
| 7.2 | Verify man pages match --help output | P0 | ☐ |
| 7.3 | Verify file paths in docs match reality | P0 | ☐ |
| 7.4 | Verify CONFIGURATION.md complete | P1 | ☐ |
| 7.5 | Verify docs/installation.md works | P1 | ☐ |
| 7.6 | Verify troubleshooting guide useful | P2 | ☐ |
| 7.7 | Documentation review report exists | P0 | ☐ |

### Exit Criteria
- All file paths in docs match installed paths
- `--help` output matches man pages
- User can install following README only

**Blockers:** Incorrect paths, misleading docs  
**Effort:** Low (already done)  
**Parallel:** Can run with Phase 6  
**Ship this phase?** YES — Documented.

---

## Phase 8: Repository Hygiene & Release Cleanup

**Objective:** Clean repository for public release.

### Entry Criteria
- Phase 6 and 7 complete

### Tasks
| # | Task | Priority | Status |
|---|------|----------|--------|
| 8.1 | Remove debug code and TODO comments | P1 | ☐ |
| 8.2 | Verify .gitignore complete | P1 | ☐ |
| 8.3 | Verify no secrets or credentials in repo | P0 | ☐ |
| 8.4 | Verify LICENSE file present | P0 | ☐ |
| 8.5 | Update CHANGELOG.md | P1 | ☐ |
| 8.6 | Tag release version in git | P0 | ☐ |
| 8.7 | Verify GitHub repo description/topics set | P2 | ☐ |

### Exit Criteria
- `git status` shows clean working tree
- Git tag v0.1.0 exists
- No sensitive data in history

**Blockers:** Secrets in repo, untagged release  
**Effort:** Low  
**Ship this phase?** YES — Ready for release.

---

## Phase 9: Final Release Gate (GO / NO-GO)

**Objective:** Make explicit ship/no-ship decision.

### Entry Criteria
- ALL previous phases complete
- project_status.md fully populated

### GO Criteria (ALL must be YES)
| # | Criterion | Status |
|---|-----------|--------|
| 9.1 | All P0 tasks across all phases complete | ☐ |
| 9.2 | No unresolved blockers | ☐ |
| 9.3 | Security audit findings addressed | ☐ |
| 9.4 | 24+ hour runtime test passed | ☐ |
| 9.5 | Clean install on fresh system works | ☐ |
| 9.6 | Man pages accessible after install | ☐ |
| 9.7 | project_status.md complete | ☐ |

### NO-GO Triggers (ANY blocks release)
- Unresolved P0 task
- Security finding not addressed
- Daemon crashes during runtime test
- State file corruption under normal operation
- Install leaves system in broken state

### Final Decision

```
[ ] GO — Ship to production
[ ] NO-GO — Return to Phase ___
```

**Sign-off Required:** _________________ Date: _________

---

## Progress Tracking Model

### Artifacts Required Per Phase
- Phase completion entry in `project_status.md`
- Test results/logs (if applicable)
- Screenshots or terminal output as evidence

### Pause & Reassess Rules
**STOP immediately if:**
1. Build fails on clean checkout
2. Daemon crashes during normal operation
3. Security vulnerability discovered
4. State file corruption detected
5. >3 P1 issues discovered in single phase

### Final Release Assertion
> "I have personally verified that:
> - All P0 items are complete
> - The daemon is safe to run as root on Kali Linux
> - No known security vulnerabilities exist
> - Documentation accurately reflects behavior
> - A user can install and run this following the README"
