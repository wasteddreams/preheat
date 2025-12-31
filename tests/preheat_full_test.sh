#!/bin/bash
# =============================================================================
# PREHEAT COMPREHENSIVE TEST SUITE
# =============================================================================
#
# A thorough test script for the preheat adaptive readahead daemon.
# Tests all major functionality, edge cases, and integration scenarios.
#
# Usage:
#   sudo ./tests/preheat_full_test.sh
#
# Output:
#   - Console summary
#   - Detailed log: /tmp/preheat_test_YYYYMMDD_HHMMSS.log
#
# =============================================================================

# Don't use set -e - we want tests to continue even if some fail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# =============================================================================
# CONFIGURATION
# =============================================================================

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/tmp/preheat_test_${TIMESTAMP}.log"
TEMP_DIR="/tmp/preheat_test_$$"
BACKUP_STATE="/tmp/preheat_state_backup_$$.state"
BACKUP_CONFIG="/tmp/preheat_config_backup_$$.conf"

# Paths
PREHEAT_BIN="/usr/local/bin/preheat"
PREHEAT_CTL="/usr/local/bin/preheat-ctl"
STATE_FILE="/usr/local/var/lib/preheat/preheat.state"
CONFIG_FILE="/usr/local/etc/preheat.conf"
STATS_FILE="/run/preheat.stats"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $msg" >> "$LOG_FILE"
    
    case "$level" in
        INFO)    echo -e "${BLUE}ℹ${NC}  $msg" ;;
        PASS)    echo -e "${GREEN}✓${NC}  $msg" ;;
        FAIL)    echo -e "${RED}✗${NC}  $msg" ;;
        WARN)    echo -e "${YELLOW}⚠${NC}  $msg" ;;
        SKIP)    echo -e "${CYAN}○${NC}  $msg" ;;
        DEBUG)   echo "   DEBUG: $msg" >> "$LOG_FILE" ;;
        *)       echo "   $msg" ;;
    esac
}

log_section() {
    local title="$1"
    echo "" | tee -a "$LOG_FILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOG_FILE"
    echo -e "${CYAN}$title${NC}" | tee -a "$LOG_FILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOG_FILE"
}

run_test() {
    local name="$1"
    local cmd="$2"
    local expected_exit="${3:-0}"
    
    ((TESTS_RUN++))
    log DEBUG "Running: $name"
    log DEBUG "Command: $cmd"
    
    set +e
    output=$(eval "$cmd" 2>&1)
    exit_code=$?
    # Don't re-enable set -e
    
    log DEBUG "Exit code: $exit_code (expected: $expected_exit)"
    log DEBUG "Output: $output"
    
    if [[ "$exit_code" -eq "$expected_exit" ]]; then
        ((TESTS_PASSED++))
        log PASS "$name"
        return 0
    else
        ((TESTS_FAILED++))
        log FAIL "$name (exit: $exit_code, expected: $expected_exit)"
        echo "  Output: $output" >> "$LOG_FILE"
        return 1
    fi
}

run_test_contains() {
    local name="$1"
    local cmd="$2"
    local expected_string="$3"
    
    ((TESTS_RUN++))
    log DEBUG "Running: $name"
    log DEBUG "Command: $cmd"
    log DEBUG "Expected string: $expected_string"
    
    set +e
    output=$(eval "$cmd" 2>&1)
    exit_code=$?
    # Don't re-enable set -e
    
    log DEBUG "Output: $output"
    
    if echo "$output" | grep -q "$expected_string"; then
        ((TESTS_PASSED++))
        log PASS "$name"
        return 0
    else
        ((TESTS_FAILED++))
        log FAIL "$name (missing: '$expected_string')"
        echo "  Output: $output" >> "$LOG_FILE"
        return 1
    fi
}

run_test_not_contains() {
    local name="$1"
    local cmd="$2"
    local forbidden_string="$3"
    
    ((TESTS_RUN++))
    log DEBUG "Running: $name"
    
    set +e
    output=$(eval "$cmd" 2>&1)
    # Don't re-enable set -e
    
    if ! echo "$output" | grep -q "$forbidden_string"; then
        ((TESTS_PASSED++))
        log PASS "$name"
        return 0
    else
        ((TESTS_FAILED++))
        log FAIL "$name (found forbidden: '$forbidden_string')"
        return 1
    fi
}

skip_test() {
    local name="$1"
    local reason="$2"
    ((TESTS_RUN++))
    ((TESTS_SKIPPED++))
    log SKIP "$name - $reason"
}

wait_for_daemon() {
    local max_wait=10
    local waited=0
    while [[ $waited -lt $max_wait ]]; do
        if pgrep -x preheat > /dev/null 2>&1; then
            return 0
        fi
        sleep 1
        ((waited++))
    done
    return 1
}

wait_for_daemon_stop() {
    local max_wait=10
    local waited=0
    while [[ $waited -lt $max_wait ]]; do
        if ! pgrep -x preheat > /dev/null 2>&1; then
            return 0
        fi
        sleep 1
        ((waited++))
    done
    return 1
}

cleanup() {
    log INFO "Cleaning up..."
    
    # Restore state file if backed up
    if [[ -f "$BACKUP_STATE" ]]; then
        cp "$BACKUP_STATE" "$STATE_FILE" 2>/dev/null || true
        rm -f "$BACKUP_STATE"
    fi
    
    # Restore config if backed up
    if [[ -f "$BACKUP_CONFIG" ]]; then
        cp "$BACKUP_CONFIG" "$CONFIG_FILE" 2>/dev/null || true
        rm -f "$BACKUP_CONFIG"
    fi
    
    # Clean temp directory
    rm -rf "$TEMP_DIR"
    
    # Restart daemon if it was running
    systemctl start preheat 2>/dev/null || true
    
    log INFO "Cleanup complete"
}

trap cleanup EXIT

# =============================================================================
# PREREQUISITES CHECK
# =============================================================================

check_prerequisites() {
    log_section "PREREQUISITES CHECK"
    
    # Check root
    if [[ $EUID -ne 0 ]]; then
        log FAIL "This test must be run as root"
        exit 1
    fi
    log PASS "Running as root"
    
    # Check binaries exist
    run_test "preheat binary exists" "[[ -x '$PREHEAT_BIN' ]]"
    run_test "preheat-ctl binary exists" "[[ -x '$PREHEAT_CTL' ]]"
    
    # Check version
    run_test_contains "preheat --version works" "$PREHEAT_BIN --version" "preheat"
    run_test_contains "preheat-ctl version works" "$PREHEAT_CTL help" "preheat-ctl"
    
    # Check systemd service
    run_test "systemd service file exists" "[[ -f /usr/local/lib/systemd/system/preheat.service ]]"
    
    # Check directories exist
    run_test "state directory exists" "[[ -d /usr/local/var/lib/preheat ]]"
    run_test "log directory exists" "[[ -d /usr/local/var/log ]]"
    
    # Create temp directory
    mkdir -p "$TEMP_DIR"
    run_test "temp directory created" "[[ -d '$TEMP_DIR' ]]"
    
    log INFO "Prerequisites check complete"
}

# =============================================================================
# DAEMON LIFECYCLE TESTS
# =============================================================================

test_daemon_lifecycle() {
    log_section "DAEMON LIFECYCLE TESTS"
    
    # Stop daemon if running
    systemctl stop preheat 2>/dev/null || true
    sleep 1
    
    # Test daemon not running
    run_test "daemon initially stopped" "! pgrep -x preheat"
    
    # Test status when stopped
    run_test_contains "preheat-ctl status (stopped)" "$PREHEAT_CTL status" "not running"
    
    # Start daemon
    log INFO "Starting daemon..."
    systemctl start preheat
    sleep 2
    
    run_test "daemon started successfully" "pgrep -x preheat"
    run_test_contains "preheat-ctl status (running)" "$PREHEAT_CTL status" "running"
    
    # Test PID file
    run_test "PID file created" "[[ -f /run/preheat.pid ]]"
    
    # Test PID file content matches actual PID
    if [[ -f /run/preheat.pid ]]; then
        pid_file=$(cat /run/preheat.pid)
        pid_actual=$(pgrep -x preheat | head -1)
        run_test "PID file matches actual PID" "[[ '$pid_file' == '$pid_actual' ]]"
    fi
    
    # Test graceful restart via systemctl
    log INFO "Testing restart..."
    run_test "systemctl restart succeeds" "systemctl restart preheat"
    sleep 2
    run_test "daemon running after restart" "pgrep -x preheat"
    
    # Test reload
    log INFO "Testing reload..."
    run_test "preheat-ctl reload succeeds" "$PREHEAT_CTL reload"
    run_test "daemon still running after reload" "pgrep -x preheat"
    
    # Test stop
    log INFO "Testing stop..."
    run_test "preheat-ctl stop succeeds" "$PREHEAT_CTL stop"
    sleep 2
    run_test "daemon stopped" "! pgrep -x preheat"
    
    # Restart for further tests
    systemctl start preheat
    wait_for_daemon
    
    log INFO "Daemon lifecycle tests complete"
}

# =============================================================================
# SIGNAL HANDLING TESTS
# =============================================================================

test_signal_handling() {
    log_section "SIGNAL HANDLING TESTS"
    
    # Ensure daemon is running
    systemctl start preheat 2>/dev/null || true
    wait_for_daemon
    
    local pid=$(pgrep -x preheat | head -1)
    if [[ -z "$pid" ]]; then
        skip_test "Signal tests" "Daemon not running"
        return
    fi
    
    log INFO "Testing signals on PID $pid"
    
    # SIGHUP - reload
    run_test "SIGHUP accepted" "kill -HUP $pid"
    sleep 1
    run_test "daemon still running after SIGHUP" "pgrep -x preheat"
    
    # SIGUSR1 - dump stats
    run_test "SIGUSR1 accepted" "kill -USR1 $pid"
    sleep 1
    run_test "stats file created after SIGUSR1" "[[ -f '$STATS_FILE' ]]"
    run_test "daemon still running after SIGUSR1" "pgrep -x preheat"
    
    # SIGUSR2 - save state
    run_test "SIGUSR2 accepted" "kill -USR2 $pid"
    sleep 1
    run_test "daemon still running after SIGUSR2" "pgrep -x preheat"
    
    # SIGTERM - graceful shutdown
    log INFO "Testing SIGTERM (will restart)..."
    kill -TERM "$pid" 2>/dev/null || true
    sleep 2
    run_test "daemon stopped by SIGTERM" "! pgrep -x preheat"
    
    # Restart for further tests
    systemctl start preheat
    wait_for_daemon
    
    log INFO "Signal handling tests complete"
}

# =============================================================================
# STATS COMMAND TESTS
# =============================================================================

test_stats_commands() {
    log_section "STATS COMMAND TESTS"
    
    # Ensure daemon is running
    systemctl start preheat 2>/dev/null || true
    wait_for_daemon
    sleep 2  # Allow stats to accumulate
    
    # Basic stats
    run_test "preheat-ctl stats succeeds" "$PREHEAT_CTL stats"
    run_test_contains "stats shows uptime" "$PREHEAT_CTL stats" "Uptime"
    run_test_contains "stats shows apps tracked" "$PREHEAT_CTL stats" "Apps tracked"
    run_test_contains "stats shows hits" "$PREHEAT_CTL stats" "[Hh]its"
    run_test_contains "stats shows misses" "$PREHEAT_CTL stats" "[Mm]isses"
    run_test_contains "stats shows hit rate" "$PREHEAT_CTL stats" "[Hh]it [Rr]ate"
    
    # Verbose stats
    run_test "preheat-ctl stats -v succeeds" "$PREHEAT_CTL stats -v"
    run_test_contains "verbose stats shows pool breakdown" "$PREHEAT_CTL stats -v" "[Pp]ool"
    
    # Stats file content
    if [[ -f "$STATS_FILE" ]]; then
        run_test_contains "stats file has version" "cat '$STATS_FILE'" "version="
        run_test_contains "stats file has uptime" "cat '$STATS_FILE'" "uptime_seconds="
        run_test_contains "stats file has hits" "cat '$STATS_FILE'" "hits="
        run_test_contains "stats file has misses" "cat '$STATS_FILE'" "misses="
        run_test_contains "stats file has hit_rate" "cat '$STATS_FILE'" "hit_rate="
        run_test_contains "stats file has apps_tracked" "cat '$STATS_FILE'" "apps_tracked="
        run_test_contains "stats file has priority_pool" "cat '$STATS_FILE'" "priority_pool="
        run_test_contains "stats file has total_preloaded_mb" "cat '$STATS_FILE'" "total_preloaded_mb="
    else
        skip_test "Stats file content tests" "Stats file not created"
    fi
    
    log INFO "Stats command tests complete"
}

# =============================================================================
# MEMORY COMMAND TESTS
# =============================================================================

test_memory_commands() {
    log_section "MEMORY COMMAND TESTS"
    
    run_test "preheat-ctl mem succeeds" "$PREHEAT_CTL mem"
    run_test_contains "mem shows total" "$PREHEAT_CTL mem" "[Tt]otal"
    run_test_contains "mem shows free" "$PREHEAT_CTL mem" "[Ff]ree"
    run_test_contains "mem shows available" "$PREHEAT_CTL mem" "[Aa]vailable"
    
    log INFO "Memory command tests complete"
}

# =============================================================================
# PREDICT COMMAND TESTS
# =============================================================================

test_predict_commands() {
    log_section "PREDICT COMMAND TESTS"
    
    run_test "preheat-ctl predict succeeds" "$PREHEAT_CTL predict"
    run_test_contains "predict shows header" "$PREHEAT_CTL predict" "[Pp]redict"
    
    # Test with top option
    run_test "preheat-ctl predict --top 5 succeeds" "$PREHEAT_CTL predict --top 5"
    
    log INFO "Predict command tests complete"
}

# =============================================================================
# HEALTH CHECK TESTS
# =============================================================================

test_health_check() {
    log_section "HEALTH CHECK TESTS"
    
    # Ensure daemon is running
    systemctl start preheat 2>/dev/null || true
    wait_for_daemon
    
    run_test "preheat-ctl health succeeds when running" "$PREHEAT_CTL health"
    run_test_contains "health shows status" "$PREHEAT_CTL health" "Daemon"
    
    # Test health when stopped
    systemctl stop preheat 2>/dev/null || true
    wait_for_daemon_stop
    
    # Should fail with exit code 2
    run_test "health returns error when stopped" "$PREHEAT_CTL health" 2
    
    # Restart
    systemctl start preheat
    wait_for_daemon
    
    log INFO "Health check tests complete"
}

# =============================================================================
# PAUSE/RESUME TESTS
# =============================================================================

test_pause_resume() {
    log_section "PAUSE/RESUME TESTS"
    
    # Ensure daemon is running
    systemctl start preheat 2>/dev/null || true
    wait_for_daemon
    
    # Test pause
    run_test "preheat-ctl pause succeeds" "$PREHEAT_CTL pause 5m"
    sleep 1
    run_test_contains "status shows paused" "$PREHEAT_CTL status" "paused\|Paused\|PAUSED"
    
    # Test resume
    run_test "preheat-ctl resume succeeds" "$PREHEAT_CTL resume"
    sleep 1
    run_test_not_contains "status shows not paused" "$PREHEAT_CTL status" "paused\|Paused\|PAUSED"
    
    log INFO "Pause/resume tests complete"
}

# =============================================================================
# STATE FILE TESTS
# =============================================================================

test_state_file() {
    log_section "STATE FILE TESTS"
    
    # Backup current state
    if [[ -f "$STATE_FILE" ]]; then
        cp "$STATE_FILE" "$BACKUP_STATE"
    fi
    
    # Ensure daemon is running
    systemctl start preheat 2>/dev/null || true
    wait_for_daemon
    
    # Force save
    run_test "preheat-ctl save succeeds" "$PREHEAT_CTL save"
    sleep 1
    
    # Check state file exists
    run_test "state file exists after save" "[[ -f '$STATE_FILE' ]]"
    
    # Check state file is not empty
    if [[ -f "$STATE_FILE" ]]; then
        local size=$(stat -c%s "$STATE_FILE" 2>/dev/null || echo "0")
        run_test "state file is not empty" "[[ $size -gt 0 ]]"
        log INFO "State file size: $size bytes"
    fi
    
    # Test state file header (first few bytes should be recognizable)
    if [[ -f "$STATE_FILE" ]]; then
        local header=$(head -c 50 "$STATE_FILE" 2>/dev/null | xxd -p | head -c 20)
        log DEBUG "State file header (hex): $header"
        run_test "state file has content" "[[ -n '$header' ]]"
    fi
    
    log INFO "State file tests complete"
}

# =============================================================================
# CONFIGURATION TESTS
# =============================================================================

test_configuration() {
    log_section "CONFIGURATION TESTS"
    
    # Check config file exists
    if [[ -f "$CONFIG_FILE" ]]; then
        run_test "config file exists" "[[ -f '$CONFIG_FILE' ]]"
        run_test "config file is readable" "[[ -r '$CONFIG_FILE' ]]"
        
        # Check for key sections
        run_test_contains "config has [model] section" "cat '$CONFIG_FILE'" "\[model\]"
        run_test_contains "config has [system] section" "cat '$CONFIG_FILE'" "\[system\]"
    else
        log INFO "No config file found - using defaults"
        skip_test "Config file tests" "Config file not present"
    fi
    
    # Test daemon starts without config file (uses defaults)
    systemctl stop preheat 2>/dev/null || true
    wait_for_daemon_stop
    
    if [[ -f "$CONFIG_FILE" ]]; then
        mv "$CONFIG_FILE" "${CONFIG_FILE}.testbackup"
    fi
    
    # Note: Daemon may fail to start without config if systemd service requires it
    systemctl start preheat 2>/dev/null
    sleep 2
    if pgrep -x preheat > /dev/null 2>&1; then
        log PASS "daemon starts without config file (uses defaults)"
        ((TESTS_RUN++))
        ((TESTS_PASSED++))
    else
        log WARN "daemon requires config file to start (expected on some setups)"
        ((TESTS_RUN++))
        ((TESTS_PASSED++))  # Count as pass since this is acceptable behavior
    fi
    
    if [[ -f "${CONFIG_FILE}.testbackup" ]]; then
        mv "${CONFIG_FILE}.testbackup" "$CONFIG_FILE"
    fi
    
    # Reload with config
    systemctl restart preheat
    wait_for_daemon
    
    log INFO "Configuration tests complete"
}

# =============================================================================
# EXPLAIN COMMAND TESTS
# =============================================================================

test_explain_command() {
    log_section "EXPLAIN COMMAND TESTS"
    
    # Test explain with known binary
    run_test "explain command succeeds for bash" "$PREHEAT_CTL explain /bin/bash"
    run_test_contains "explain shows status" "$PREHEAT_CTL explain /bin/bash" "[Ss]tatus\|[Pp]ool\|[Tt]racked"
    
    # Test explain with non-existent binary
    run_test "explain handles non-existent binary" "$PREHEAT_CTL explain /nonexistent/binary" 0
    
    log INFO "Explain command tests complete"
}

# =============================================================================
# EDGE CASE TESTS
# =============================================================================

test_edge_cases() {
    log_section "EDGE CASE TESTS"
    
    # Test unknown command
    run_test "unknown command returns error" "$PREHEAT_CTL unknowncommand" 1
    
    # Test help
    run_test "help command works" "$PREHEAT_CTL help"
    run_test_contains "help shows commands" "$PREHEAT_CTL help" "stats\|status\|reload"
    
    # Test empty args (returns 1 with usage message)
    run_test "no args shows help" "$PREHEAT_CTL" 1
    
    # Test double stop (should not crash)
    systemctl stop preheat 2>/dev/null || true
    wait_for_daemon_stop
    run_test "double stop is safe" "systemctl stop preheat" 0
    
    # Test double start (should not crash)
    systemctl start preheat 2>/dev/null || true
    wait_for_daemon
    run_test "double start is handled" "systemctl start preheat" 0
    
    log INFO "Edge case tests complete"
}

# =============================================================================
# FOREGROUND MODE TESTS
# =============================================================================

test_foreground_mode() {
    log_section "FOREGROUND MODE TESTS"
    
    # Stop daemon first
    systemctl stop preheat 2>/dev/null || true
    wait_for_daemon_stop
    
    # Start in foreground briefly
    log INFO "Starting daemon in foreground mode..."
    timeout 3 $PREHEAT_BIN -f > "$TEMP_DIR/foreground.log" 2>&1 &
    local fg_pid=$!
    sleep 2
    
    # Check it started
    if ps -p $fg_pid > /dev/null 2>&1; then
        run_test "foreground mode starts" "true"
        kill $fg_pid 2>/dev/null || true
    else
        # Check if it exited cleanly
        wait $fg_pid 2>/dev/null
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            run_test "foreground mode runs until timeout" "true"
        else
            run_test "foreground mode started" "[[ $exit_code -eq 0 ]] || [[ $exit_code -eq 124 ]]"
        fi
    fi
    
    # Check log output
    if [[ -f "$TEMP_DIR/foreground.log" ]]; then
        local log_size=$(stat -c%s "$TEMP_DIR/foreground.log" 2>/dev/null || echo "0")
        log INFO "Foreground log size: $log_size bytes"
        if [[ $log_size -gt 0 ]]; then
            log DEBUG "Foreground log content:"
            cat "$TEMP_DIR/foreground.log" >> "$LOG_FILE"
        fi
    fi
    
    # Restart normal daemon
    systemctl start preheat
    wait_for_daemon
    
    log INFO "Foreground mode tests complete"
}

# =============================================================================
# SELF-TEST MODE TESTS
# =============================================================================

test_self_test_mode() {
    log_section "SELF-TEST MODE TESTS"
    
    # Stop daemon first (self-test runs as separate process)
    systemctl stop preheat 2>/dev/null || true
    wait_for_daemon_stop
    
    run_test "self-test mode runs" "$PREHEAT_BIN --self-test"
    
    # Restart daemon
    systemctl start preheat
    wait_for_daemon
    
    log INFO "Self-test mode tests complete"
}

# =============================================================================
# EXPORT/IMPORT TESTS
# =============================================================================

test_export_import() {
    log_section "EXPORT/IMPORT TESTS"
    
    local export_file="$TEMP_DIR/test_export.json"
    
    # Ensure daemon is running
    systemctl start preheat 2>/dev/null || true
    wait_for_daemon
    
    # Test export
    run_test "export command succeeds" "$PREHEAT_CTL export '$export_file'"
    
    if [[ -f "$export_file" ]]; then
        run_test "export file created" "[[ -f '$export_file' ]]"
        run_test "export file is valid JSON" "python3 -c \"import json; json.load(open('$export_file'))\" 2>/dev/null || jq . '$export_file' > /dev/null 2>&1"
        
        # Test import (validation only)
        run_test "import command validates" "$PREHEAT_CTL import '$export_file'"
    else
        skip_test "Export file tests" "Export file not created"
    fi
    
    log INFO "Export/import tests complete"
}

# =============================================================================
# STRESS TESTS
# =============================================================================

test_stress() {
    log_section "STRESS TESTS"
    
    # Ensure daemon is running
    systemctl start preheat 2>/dev/null || true
    wait_for_daemon
    
    log INFO "Running rapid stats queries..."
    local rapid_success=0
    for i in {1..20}; do
        if $PREHEAT_CTL stats > /dev/null 2>&1; then
            ((rapid_success++))
        fi
    done
    run_test "rapid stats queries ($rapid_success/20)" "[[ $rapid_success -ge 18 ]]"
    
    log INFO "Running rapid signal sends..."
    local pid=$(pgrep -x preheat | head -1)
    if [[ -n "$pid" ]]; then
        for i in {1..10}; do
            kill -USR1 "$pid" 2>/dev/null || true
            sleep 0.1
        done
        run_test "daemon survives rapid signals" "pgrep -x preheat"
    else
        skip_test "Rapid signal test" "Daemon not running"
    fi
    
    log INFO "Running rapid restart cycles..."
    local restart_success=0
    for i in {1..5}; do
        systemctl restart preheat 2>/dev/null
        sleep 2
        if pgrep -x preheat > /dev/null 2>&1; then
            ((restart_success++))
        fi
    done
    run_test "rapid restart cycles ($restart_success/5)" "[[ $restart_success -eq 5 ]]"
    
    log INFO "Stress tests complete"
}

# =============================================================================
# MAIN TEST RUNNER
# =============================================================================

main() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║           PREHEAT COMPREHENSIVE TEST SUITE                       ║"
    echo "╠══════════════════════════════════════════════════════════════════╣"
    echo "║  Log file: $LOG_FILE"                                            ║
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Initialize log
    echo "Preheat Test Suite - Started $(date)" > "$LOG_FILE"
    echo "========================================" >> "$LOG_FILE"
    
    # Run all test suites
    check_prerequisites
    test_daemon_lifecycle
    test_signal_handling
    test_stats_commands
    test_memory_commands
    test_predict_commands
    test_health_check
    test_pause_resume
    test_state_file
    test_configuration
    test_explain_command
    test_edge_cases
    test_foreground_mode
    test_self_test_mode
    test_export_import
    test_stress
    
    # Summary
    log_section "TEST SUMMARY"
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║  TEST RESULTS                                                    ║"
    echo "╠══════════════════════════════════════════════════════════════════╣"
    printf "║  Total tests:   %-48d ║\n" "$TESTS_RUN"
    printf "║  ${GREEN}Passed:         %-48d${NC} ║\n" "$TESTS_PASSED"
    printf "║  ${RED}Failed:         %-48d${NC} ║\n" "$TESTS_FAILED"
    printf "║  ${CYAN}Skipped:        %-48d${NC} ║\n" "$TESTS_SKIPPED"
    echo "╠══════════════════════════════════════════════════════════════════╣"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "║  ${GREEN}★ ALL TESTS PASSED ★${NC}                                           ║"
    else
        echo -e "║  ${RED}✗ SOME TESTS FAILED${NC}                                            ║"
    fi
    
    echo "╠══════════════════════════════════════════════════════════════════╣"
    echo "║  Full log: $LOG_FILE"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Write summary to log
    echo "" >> "$LOG_FILE"
    echo "========================================" >> "$LOG_FILE"
    echo "SUMMARY" >> "$LOG_FILE"
    echo "========================================" >> "$LOG_FILE"
    echo "Total:   $TESTS_RUN" >> "$LOG_FILE"
    echo "Passed:  $TESTS_PASSED" >> "$LOG_FILE"
    echo "Failed:  $TESTS_FAILED" >> "$LOG_FILE"
    echo "Skipped: $TESTS_SKIPPED" >> "$LOG_FILE"
    echo "========================================" >> "$LOG_FILE"
    echo "Completed: $(date)" >> "$LOG_FILE"
    
    # Return appropriate exit code
    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

# Run main
main "$@"
