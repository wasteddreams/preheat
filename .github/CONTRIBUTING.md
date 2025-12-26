# Contributing to Preheat

Thank you for considering contributing to preheat! 🎉

We welcome contributions of all kinds - bug reports, feature requests, documentation improvements, and code contributions.

## Quick Start

```bash
# Clone and build
git clone https://github.com/wasteddreams/preheat-linux.git
cd preheat-linux
autoreconf --install --force
./configure
make -j$(nproc)

# Install and test
sudo make install
sudo systemctl restart preheat
preheat-ctl stats
```

## Ways to Contribute

### 🐛 Bug Reports

Found a bug? Help us squash it:

1. Check [existing issues](../../issues) to avoid duplicates
2. Use the [bug report template](ISSUE_TEMPLATE/bug_report.md)
3. Include logs: `sudo tail -100 /usr/local/var/log/preheat.log`
4. Provide reproduction steps

### 💡 Feature Requests

Have an idea? We'd love to hear it:

1. Use the [feature request template](ISSUE_TEMPLATE/feature_request.md)
2. Explain the use case and benefits
3. Consider backward compatibility

### 🔧 Pull Requests

Ready to code? Here's how:

1. **Fork** the repository
2. **Create a branch**: `git checkout -b feature/amazing-feature`
3. **Make changes** following our coding guidelines
4. **Test thoroughly** (see below)
5. **Commit** with clear, descriptive messages
6. **Push** and open a Pull Request

## Coding Guidelines

### Style

- **Language**: C99 standard
- **Indentation**: 4 spaces (no tabs)
- **Braces**: Opening brace on new line for functions
- **Line length**: 100 characters max
- **Comments**: C-style `/* */` for multi-line, `//` for single line

### Best Practices

```c
/* Good: Clear function with proper error handling */
static int
process_application(const char *path, app_info_t *info)
{
    int result = -1;
    char *resolved = NULL;
    
    if (!path || !info) {
        g_warning("Invalid parameters");
        return -EINVAL;
    }
    
    resolved = realpath(path, NULL);
    if (!resolved) {
        goto cleanup;
    }
    
    /* Process the resolved path */
    result = 0;
    
cleanup:
    free(resolved);
    return result;
}
```

### Requirements

- ✅ All functions must check return values
- ✅ No memory leaks (use `valgrind` to verify)
- ✅ Consistent error handling with `goto cleanup`
- ✅ GLib functions preferred (`g_strdup`, `g_free`, etc.)
- ✅ Comments for complex logic

## Testing

### Before Submitting

```bash
# Clean build
make clean && ./configure && make -j$(nproc)

# Install and verify daemon starts
sudo make install
sudo systemctl restart preheat
sudo preheat-ctl status

# Check for warnings during build
make 2>&1 | grep -i warning

# Run with valgrind (optional but appreciated)
sudo valgrind --leak-check=full ./src/preheat --foreground
```

### What We Test

- Daemon starts and stops cleanly
- State file loads and saves correctly
- Classification logic works for GUI vs system apps
- No memory leaks on shutdown
- Graceful handling of missing files/permissions

## Project Structure

```
preheat/
├── src/
│   ├── daemon/     # Core daemon (main, signals, stats)
│   ├── monitor/    # Process monitoring (proc, spy)
│   ├── predict/    # Prediction engine
│   ├── readahead/  # Preloading implementation
│   ├── state/      # State persistence
│   ├── config/     # Configuration handling
│   └── utils/      # Utilities (logging, patterns)
├── tools/          # CLI tool (preheat-ctl)
├── docs/           # Documentation
└── man/            # Man pages
```

## Documentation

When adding features, update:

| File | Purpose |
|------|---------|
| `README.md` | Quick start and overview |
| `docs/` | Detailed guides |
| `man/` | Man pages (groff format) |
| `CHANGELOG.md` | Version history |

## Review Process

1. All PRs require at least one approval
2. CI must pass (build, basic tests)
3. Significant changes need documentation updates
4. Breaking changes need migration notes

## Recognition

Contributors are recognized in:
- `CHANGELOG.md` for notable contributions
- GitHub contributors list

## Questions?

- Open a [Discussion](../../discussions) for questions
- Join existing issues to help others
- Check `docs/` for detailed documentation

## License

By contributing, you agree that your contributions will be licensed under the **GNU General Public License v2** (GPL-2.0).

---

**Thank you for making preheat better!** 🚀
