---
name: Bug Report
about: Report a bug or issue with preheat daemon
title: '[BUG] '
labels: bug
assignees: ''
---

## Bug Description

**Summary**: <!-- One-line description of the bug -->

**Severity**: <!-- Critical / High / Medium / Low -->

## Environment

| Component | Value |
|-----------|-------|
| OS | <!-- e.g., Kali Linux 2024.4 --> |
| Kernel | <!-- output of `uname -r` --> |
| Preheat Version | <!-- output of `preheat-ctl --version` --> |
| RAM | <!-- output of `free -h | grep Mem` --> |
| CPU | <!-- output of `nproc` cores --> |

## Steps to Reproduce

1. 
2. 
3. 

## Expected Behavior

<!-- What should have happened? -->

## Actual Behavior

<!-- What actually happened? Include error messages if any -->

## Logs

### Daemon Log
```
<!-- Paste output from: sudo tail -100 /usr/local/var/log/preheat.log -->
```

### Systemd Status
```
<!-- Paste output from: sudo systemctl status preheat -->
```

### State Info (if applicable)
```
<!-- Paste output from: sudo preheat-ctl stats -v -->
```

## Diagnostic Commands

Run these and paste output if relevant:

```bash
# Daemon status
sudo preheat-ctl status

# Pool breakdown
sudo preheat-ctl stats -v | head -30

# Specific app status (if app-related)
sudo preheat-ctl explain <app-name>

# State file info
ls -la /usr/local/var/lib/preheat/
```

## Additional Context

<!-- Screenshots, config changes, recent system updates, etc. -->

## Possible Fix

<!-- If you have ideas about what might be causing this -->

---

**Checklist**:
- [ ] I searched existing issues for duplicates
- [ ] I included relevant logs
- [ ] I can reproduce this consistently
