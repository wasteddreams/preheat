#!/bin/bash
# Comprehensive Integration Test for Preheat
# Tests: Configuration, State, Monitoring, Prediction, Preloading, Signals

set -e

echo "========================================="
echo "Preheat Integration Test Suite"
echo "Complete Daemon Functionality"
echo "========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Setup test environment
TEST_DIR="/tmp/preheat-integration-$$"
mkdir -p "$TEST_DIR"/{etc,var/lib/preheat,var/log}

echo "Test environment: $TEST_DIR"
echo ""

# Cleanup function
cleanup() {
    if [ -f "$TEST_DIR/daemon.pid" ]; then
        PID=$(cat "$TEST_DIR/daemon.pid")
        if ps -p $PID > /dev/null; then
            echo "Cleaning up daemon (PID: $PID)..."
            kill $PID 2>/dev/null || true
            sleep 1
        fi
    fi
}
trap cleanup EXIT

# Test helper functions
test_start() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "TEST $TESTS_RUN: $1... "
}

test_pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}PASS${NC}"
}

test_fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}FAIL${NC}"
    if [ -n "$1" ]; then
        echo "  Error: $1"
    fi
}

# =========================================================================
# TEST 1: Binary Verification
# =========================================================================
test_start "Binary exists and is executable"
if [ -x "./src/preheat" ]; then
    test_pass
else
    test_fail "Binary not found or not executable"
    exit 1
fi

# =========================================================================
# TEST 2: Version Check
# =========================================================================
test_start "Version command works"
VERSION_OUTPUT=$(./src/preheat --version 2>&1)
if echo "$VERSION_OUTPUT" | grep -q "preheat 0.1.0"; then
    test_pass
else
    test_fail "Version output incorrect"
fi

# =========================================================================
# TEST 3: Configuration File
# =========================================================================
test_start "Configuration file setup"
cp config/preheat.conf.default "$TEST_DIR/etc/preheat.conf"
# Modify config for testing
cat >> "$TEST_DIR/etc/preheat.conf" << EOF

# Test configuration
[model]
cycle = 6
minsize = 1000000

[system]
doscan = true
dopredict = true
autosave = 30
maxprocs = 2
EOF

if [ -f "$TEST_DIR/etc/preheat.conf" ]; then
    test_pass
else
    test_fail "Config file not created"
fi

# =========================================================================
# TEST 4: Daemon Startup (Foreground)
# =========================================================================
test_start "Daemon starts in foreground mode"
timeout 2 ./src/preheat -f \
    -c "$TEST_DIR/etc/preheat.conf" \
    -s "$TEST_DIR/var/lib/preheat/state.bin" \
    -l "$TEST_DIR/var/log/preheat.log" \
    2>&1 > /dev/null || true

if [ -f "$TEST_DIR/var/log/preheat.log" ]; then
    test_pass
else
    test_fail "Log file not created"
fi

# =========================================================================
# TEST 5: Configuration Loading
# =========================================================================
test_start "Configuration loads correctly"
if grep -q "loading configuration" "$TEST_DIR/var/log/preheat.log"; then
    test_pass
else
    test_fail "Config not loaded"
fi

# =========================================================================
# TEST 6: State Initialization
# =========================================================================
test_start "State initializes without errors"
if ! grep -q "error.*state" "$TEST_DIR/var/log/preheat.log"; then
    test_pass
else
    test_fail "State initialization errors found"
fi

# =========================================================================
# TEST 7: Daemon Background Mode
# =========================================================================
test_start "Daemon runs in background"
rm -f "$TEST_DIR/var/log/preheat.log"

# Start daemon in background
./src/preheat \
    -c "$TEST_DIR/etc/preheat.conf" \
    -s "$TEST_DIR/var/lib/preheat/state.bin" \
    -l "$TEST_DIR/var/log/preheat.log" \
    > /dev/null 2>&1 &

DAEMON_PID=$!
echo $DAEMON_PID > "$TEST_DIR/daemon.pid"
sleep 2

if ps -p $DAEMON_PID > /dev/null; then
    test_pass
else
    test_fail "Daemon not running"
fi

# =========================================================================
# TEST 8: Periodic Scanning
# =========================================================================
test_start "Periodic scanning activates"
sleep 8  # Wait for at least one scan cycle (cycle=6s)

if grep -q "state scanning begin" "$TEST_DIR/var/log/preheat.log"; then
    test_pass
else
    test_fail "No scanning activity detected"
fi

# =========================================================================
# TEST 9: Process Monitoring
# =========================================================================
test_start "Process monitoring works"
if grep -q "scanning" "$TEST_DIR/var/log/preheat.log"; then
    test_pass
else
    test_fail "No monitoring activity"
fi

# =========================================================================
# TEST 10: Prediction Execution
# =========================================================================
test_start "Prediction engine runs"
if grep -q "predicting" "$TEST_DIR/var/log/preheat.log"; then
    test_pass
else
    test_fail "No prediction activity"
fi

# =========================================================================
# TEST 11: Signal Handling - SIGUSR1 (Dump State)
# =========================================================================
test_start "SIGUSR1 signal (dump state)"
if ps -p $DAEMON_PID > /dev/null; then
    kill -USR1 $DAEMON_PID
    sleep 1
    if grep -q "state log dump" "$TEST_DIR/var/log/preheat.log"; then
        test_pass
    else
        test_fail "Dump command not executed"
    fi
else
    test_fail "Daemon not running"
fi

# =========================================================================
# TEST 12: Signal Handling - SIGUSR2 (Save State)
# =========================================================================
test_start "SIGUSR2 signal (save state)"
if ps -p $DAEMON_PID > /dev/null; then
    kill -USR2 $DAEMON_PID
    sleep 1
    if grep -q "saving state" "$TEST_DIR/var/log/preheat.log"; then
        test_pass
    else
        test_fail "Save command not executed"
    fi
else
    test_fail "Daemon not running"
fi

# =========================================================================
# TEST 13: State File Creation
# =========================================================================
test_start "State file is created"
# Wait for autosave or trigger it
kill -USR2 $DAEMON_PID 2>/dev/null || true
sleep 2

if [ -f "$TEST_DIR/var/lib/preheat/state.bin" ]; then
    test_pass
else
    test_fail "State file not created"
fi

# =========================================================================
# TEST 14: State File Format
# =========================================================================
test_start "State file has valid format"
if [ -f "$TEST_DIR/var/lib/preheat/state.bin" ]; then
    if head -1 "$TEST_DIR/var/lib/preheat/state.bin" | grep -q "PRELOAD"; then
        test_pass
    else
        test_fail "State file format invalid"
    fi
else
    test_fail "State file doesn't exist"
fi

# =========================================================================
# TEST 15: Signal Handling - SIGHUP (Reload Config)
# =========================================================================
test_start "SIGHUP signal (reload config)"
if ps -p $DAEMON_PID > /dev/null; then
    # Modify config
    echo "# Reloaded" >> "$TEST_DIR/etc/preheat.conf"
    kill -HUP $DAEMON_PID
    sleep 1
    # Count how many times config was loaded
    LOAD_COUNT=$(grep -c "loading configuration" "$TEST_DIR/var/log/preheat.log")
    if [ "$LOAD_COUNT" -ge 2 ]; then
        test_pass
    else
        test_fail "Config not reloaded (count: $LOAD_COUNT)"
    fi
else
    test_fail "Daemon not running"
fi

# =========================================================================
# TEST 16: Memory Stats Collection
# =========================================================================
test_start "Memory statistics collected"
if grep -q "available for preloading" "$TEST_DIR/var/log/preheat.log"; then
    test_pass
else
    test_fail "No memory stats in log"
fi

# =========================================================================
# TEST 17: Graceful Shutdown - SIGTERM
# =========================================================================
test_start "SIGTERM signal (graceful shutdown)"
if ps -p $DAEMON_PID > /dev/null; then
    kill -TERM $DAEMON_PID
    sleep 2
    if ! ps -p $DAEMON_PID > /dev/null 2>&1; then
        test_pass
    else
        test_fail "Daemon still running after SIGTERM"
        kill -9 $DAEMON_PID 2>/dev/null || true
    fi
else
    test_fail "Daemon not running"
fi

# =========================================================================
# TEST 18: State Persistence Across Restarts
# =========================================================================
test_start "State persists across restarts"
# Start daemon again
./src/preheat \
    -c "$TEST_DIR/etc/preheat.conf" \
    -s "$TEST_DIR/var/lib/preheat/state.bin" \
    -l "$TEST_DIR/var/log/preheat.log.2" \
    > /dev/null 2>&1 &

DAEMON_PID=$!
echo $DAEMON_PID > "$TEST_DIR/daemon.pid"
sleep 2

if grep -q "loading state from" "$TEST_DIR/var/log/preheat.log.2"; then
    test_pass
    kill -TERM $DAEMON_PID 2>/dev/null || true
    sleep 1
else
    test_fail "State not loaded on restart"
    kill -TERM $DAEMON_PID 2>/dev/null || true
fi

# =========================================================================
# TEST 19: Log File Content Analysis
# =========================================================================
test_start "Log file has expected content"
LOG_ERRORS=$(grep -i "critical\|error" "$TEST_DIR/var/log/preheat.log" | grep -v "error adding symbols" | wc -l)
if [ "$LOG_ERRORS" -eq 0 ]; then
    test_pass
else
    test_fail "Found $LOG_ERRORS error/critical messages in log"
fi

# =========================================================================
# TEST 20: Code Coverage Summary
# =========================================================================
test_start "All major components tested"
COMPONENTS_TESTED=0

grep -q "loading configuration" "$TEST_DIR/var/log/preheat.log" && COMPONENTS_TESTED=$((COMPONENTS_TESTED + 1))
grep -q "scanning" "$TEST_DIR/var/log/preheat.log" && COMPONENTS_TESTED=$((COMPONENTS_TESTED + 1))
grep -q "predicting" "$TEST_DIR/var/log/preheat.log" && COMPONENTS_TESTED=$((COMPONENTS_TESTED + 1))
grep -q "saving state" "$TEST_DIR/var/log/preheat.log" && COMPONENTS_TESTED=$((COMPONENTS_TESTED + 1))
[ -f "$TEST_DIR/var/lib/preheat/state.bin" ] && COMPONENTS_TESTED=$((COMPONENTS_TESTED + 1))

if [ "$COMPONENTS_TESTED" -ge 5 ]; then
    test_pass
else
    test_fail "Only $COMPONENTS_TESTED/5 components verified"
fi

# =========================================================================
# Summary
# =========================================================================
echo ""
echo "========================================="
echo "TEST SUMMARY"
echo "========================================="
echo "Total Tests: $TESTS_RUN"
echo -e "Passed:      ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed:      ${RED}$TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ ALL TESTS PASSED${NC}"
    echo ""
    echo "Daemon Functionality Verified:"
    echo "  ✓ Configuration loading"
    echo "  ✓ State persistence (load/save)"
    echo "  ✓ Process monitoring"
    echo "  ✓ Prediction engine"
    echo "  ✓ Periodic tasks"
    echo "  ✓ Signal handling (HUP/USR1/USR2/TERM)"
    echo "  ✓ Graceful shutdown"
    echo "  ✓ Daemon restart with state"
    echo ""
    echo "Test artifacts in: $TEST_DIR"
    echo ""
    EXIT_CODE=0
else
    echo -e "${RED}✗ SOME TESTS FAILED${NC}"
    echo ""
    echo "Check logs in: $TEST_DIR/var/log/"
    echo ""
    EXIT_CODE=1
fi

echo "========================================="
exit $EXIT_CODE
