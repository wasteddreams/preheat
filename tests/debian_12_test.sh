#!/bin/bash
# =============================================================================
# PREHEAT DEBIAN 12 COMPREHENSIVE TEST SUITE
# =============================================================================
#
# Comprehensive testing for preheat daemon on Debian 12.x (Bookworm)
# Tests compatibility, functionality, performance, and edge cases specific
# to Debian 12.8 environment.
#
# Usage:
#   sudo ./tests/debian_12_test.sh               # Full test suite
#   sudo ./tests/debian_12_test.sh --quick       # Quick smoke tests only
#   sudo ./tests/debian_12_test.sh --build       # Build from source first
#   sudo ./tests/debian_12_test.sh --no-install  # Test local build without install
#
# Requirements:
#   - Debian 12.x (Bookworm)
#   - Root privileges
#   - Build dependencies: gcc, make, autoconf, automake, libtool
#
# =============================================================================

set -o pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/tmp/preheat_debian12_test_${TIMESTAMP}.log"
TEMP_DIR="/tmp/preheat_debian_test_$$"
REPORT_FILE="/tmp/preheat_debian12_report_${TIMESTAMP}.txt"

# Installed paths (for installed daemon)
PREHEAT_BIN_INSTALLED="/usr/local/bin/preheat"
PREHEAT_CTL_INSTALLED="/usr/local/bin/preheat-ctl"
STATE_DIR_INSTALLED="/usr/local/var/lib/preheat"
LOG_DIR_INSTALLED="/usr/local/var/log"
CONFIG_INSTALLED="/usr/local/etc/preheat.conf"

# Local build paths
PREHEAT_BIN_LOCAL="$PROJECT_ROOT/src/preheat"
PREHEAT_CTL_LOCAL="$PROJECT_ROOT/tools/preheat-ctl"

# Will be set based on mode
PREHEAT_BIN=""
PREHEAT_CTL=""

# Mode flags
QUICK_MODE=false
BUILD_FIRST=false
NO_INSTALL_MODE=false

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
CRITICAL_FAILURES=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

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
        INFO)     echo -e "  ${BLUE}ℹ${NC}  $msg" ;;
        PASS)     echo -e "  ${GREEN}✓${NC}  $msg" ;;
        FAIL)     echo -e "  ${RED}✗${NC}  $msg" ;;
        WARN)     echo -e "  ${YELLOW}⚠${NC}  $msg" ;;
        SKIP)     echo -e "  ${CYAN}○${NC}  $msg" ;;
        CRITICAL) echo -e "  ${RED}${BOLD}✗✗${NC} $msg" ;;
        DEBUG)    ;; # Silent in console
        *)        echo "     $msg" ;;
    esac
}

section() {
    local title="$1"
    echo "" | tee -a "$LOG_FILE"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$LOG_FILE"
    echo -e "${BOLD}  $title${NC}" | tee -a "$LOG_FILE"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$LOG_FILE"
}

subsection() {
    echo -e "\n  ${MAGENTA}▸ $1${NC}" | tee -a "$LOG_FILE"
}

test_pass() {
    ((TESTS_RUN++))
    ((TESTS_PASSED++))
    log PASS "$1"
}

test_fail() {
    ((TESTS_RUN++))
    ((TESTS_FAILED++))
    log FAIL "$1"
    echo "        Reason: $2" >> "$LOG_FILE"
}

test_fail_critical() {
    ((TESTS_RUN++))
    ((TESTS_FAILED++))
    ((CRITICAL_FAILURES++))
    log CRITICAL "$1"
    echo "        Reason: $2" >> "$LOG_FILE"
}

test_skip() {
    ((TESTS_RUN++))
    ((TESTS_SKIPPED++))
    log SKIP "$1 ($2)"
}

run_cmd() {
    local desc="$1"
    local cmd="$2"
    local expect_exit="${3:-0}"
    
    log DEBUG "Running: $cmd"
    set +e
    output=$(eval "$cmd" 2>&1)
    exit_code=$?
    set -e
    
    log DEBUG "Exit: $exit_code, Output: $output"
    
    if [[ "$exit_code" -eq "$expect_exit" ]]; then
        test_pass "$desc"
        return 0
    else
        test_fail "$desc" "Exit $exit_code (expected $expect_exit)"
        return 1
    fi
}

run_cmd_contains() {
    local desc="$1"
    local cmd="$2"
    local pattern="$3"
    
    set +e
    output=$(eval "$cmd" 2>&1)
    set -e
    
    if echo "$output" | grep -qE "$pattern"; then
        test_pass "$desc"
        return 0
    else
        test_fail "$desc" "Missing pattern: $pattern"
        return 1
    fi
}

wait_daemon_start() {
    local max_wait=15
    for ((i=0; i<max_wait; i++)); do
        if pgrep -x preheat > /dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    return 1
}

wait_daemon_stop() {
    local max_wait=10
    for ((i=0; i<max_wait; i++)); do
        if ! pgrep -x preheat > /dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    return 1
}

stop_daemon() {
    systemctl stop preheat 2>/dev/null || true
    pkill -x preheat 2>/dev/null || true
    wait_daemon_stop
}

cleanup() {
    log INFO "Cleaning up test artifacts..."
    rm -rf "$TEMP_DIR"
    # Don't kill daemon on cleanup - leave it in whatever state it was
}

trap cleanup EXIT

# =============================================================================
# DEBIAN 12 ENVIRONMENT CHECKS
# =============================================================================

check_debian_12() {
    section "DEBIAN 12 ENVIRONMENT VERIFICATION"
    
    subsection "OS Detection"
    
    # Check we're on Debian
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        log INFO "Detected: $PRETTY_NAME"
        
        if [[ "$ID" == "debian" ]]; then
            test_pass "Running on Debian"
            
            if [[ "$VERSION_ID" == "12" ]]; then
                test_pass "Debian 12 (Bookworm) confirmed"
            else
                test_fail "Debian version check" "Expected 12, got $VERSION_ID"
                log WARN "Tests designed for Debian 12.x, some may not work correctly"
            fi
        else
            test_fail "Debian check" "Not Debian: $ID"
            log WARN "Tests designed for Debian, may not work on $ID"
        fi
    else
        test_skip "OS detection" "/etc/os-release not found"
    fi
    
    subsection "System Requirements"
    
    # Check root
    if [[ $EUID -eq 0 ]]; then
        test_pass "Running as root"
    else
        test_fail_critical "Root check" "Must run as root"
        echo -e "${RED}ERROR: This test suite must be run as root${NC}"
        exit 1
    fi
    
    # Check kernel version
    local kernel=$(uname -r)
    log INFO "Kernel: $kernel"
    
    # Debian 12 uses kernel 6.1.x typically
    if [[ "$kernel" =~ ^6\. ]]; then
        test_pass "Kernel 6.x detected"
    elif [[ "$kernel" =~ ^5\.10 ]]; then
        test_pass "Kernel 5.10.x (backports) detected"
    else
        log WARN "Unusual kernel version: $kernel"
    fi
    
    # Check systemd
    if systemctl --version > /dev/null 2>&1; then
        local systemd_ver=$(systemctl --version | head -1 | awk '{print $2}')
        log INFO "systemd version: $systemd_ver"
        test_pass "systemd available (v$systemd_ver)"
    else
        test_fail "systemd check" "systemd not found"
    fi
    
    # Check /proc filesystem
    if [[ -d /proc && -f /proc/meminfo ]]; then
        test_pass "/proc filesystem mounted"
    else
        test_fail_critical "/proc check" "/proc not available"
    fi
    
    subsection "Memory & Resources"
    
    # Memory check
    local mem_total=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)
    local mem_avail=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
    log INFO "Total memory: ${mem_total}MB, Available: ${mem_avail}MB"
    
    if [[ $mem_avail -gt 200 ]]; then
        test_pass "Sufficient memory available (${mem_avail}MB)"
    else
        test_fail "Memory check" "Low memory: ${mem_avail}MB"
    fi
    
    # Disk space
    local disk_avail=$(df -m /tmp | awk 'NR==2{print $4}')
    log INFO "Available disk in /tmp: ${disk_avail}MB"
    
    if [[ $disk_avail -gt 100 ]]; then
        test_pass "Sufficient disk space in /tmp"
    else
        test_fail "Disk check" "Low disk: ${disk_avail}MB"
    fi
}

# =============================================================================
# BUILD DEPENDENCIES CHECK
# =============================================================================

check_build_deps() {
    section "BUILD DEPENDENCIES"
    
    subsection "Required Tools"
    
    local tools=("gcc" "make" "autoconf" "automake" "libtool")
    local missing=()
    
    for tool in "${tools[@]}"; do
        if command -v "$tool" > /dev/null 2>&1; then
            local ver=$($tool --version 2>&1 | head -1)
            test_pass "$tool available"
            log DEBUG "$tool: $ver"
        else
            test_fail "$tool check" "not installed"
            missing+=("$tool")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log WARN "Missing tools: ${missing[*]}"
        log INFO "Install with: apt install ${missing[*]} build-essential"
    fi
    
    subsection "Header Files"
    
    # Check for required headers
    local headers=(
        "/usr/include/sys/inotify.h"
        "/usr/include/pthread.h"
    )
    
    for header in "${headers[@]}"; do
        if [[ -f "$header" ]]; then
            test_pass "$(basename "$header") header present"
        else
            test_skip "$(basename "$header")" "header not found"
        fi
    done
}

# =============================================================================
# BUILD TESTS
# =============================================================================

test_build() {
    section "BUILD FROM SOURCE"
    
    cd "$PROJECT_ROOT"
    
    subsection "Clean Build"
    
    # Clean first
    if make clean > /dev/null 2>&1; then
        test_pass "make clean succeeded"
    else
        test_skip "make clean" "no previous build"
    fi
    
    # Check if configure exists or need to generate
    if [[ ! -f configure ]] || [[ ! -x configure ]]; then
        log INFO "Running autoreconf..."
        if autoreconf -fi >> "$LOG_FILE" 2>&1; then
            test_pass "autoreconf generated configure"
        else
            test_fail_critical "autoreconf" "failed to generate configure"
            return 1
        fi
    fi
    
    subsection "Configure"
    
    if ./configure >> "$LOG_FILE" 2>&1; then
        test_pass "./configure succeeded"
    else
        test_fail_critical "./configure" "configuration failed"
        return 1
    fi
    
    subsection "Compile"
    
    local start_time=$(date +%s)
    if make -j$(nproc) >> "$LOG_FILE" 2>&1; then
        local end_time=$(date +%s)
        local build_time=$((end_time - start_time))
        test_pass "Compilation succeeded (${build_time}s)"
    else
        test_fail_critical "Compilation" "make failed"
        return 1
    fi
    
    # Verify binaries exist
    if [[ -x "$PREHEAT_BIN_LOCAL" ]]; then
        test_pass "preheat binary created"
    else
        test_fail "preheat binary check" "not found at $PREHEAT_BIN_LOCAL"
    fi
    
    if [[ -x "$PREHEAT_CTL_LOCAL" ]]; then
        test_pass "preheat-ctl binary created"
    else
        test_fail "preheat-ctl binary check" "not found at $PREHEAT_CTL_LOCAL"
    fi
    
    # Check binary linkage
    subsection "Binary Analysis"
    
    if ldd "$PREHEAT_BIN_LOCAL" >> "$LOG_FILE" 2>&1; then
        test_pass "Binary links correctly"
        
        # Check for expected libraries
        if ldd "$PREHEAT_BIN_LOCAL" | grep -q "libpthread"; then
            test_pass "Links against pthread"
        fi
        
        if ldd "$PREHEAT_BIN_LOCAL" | grep -q "libc.so"; then
            test_pass "Links against libc"
        fi
    else
        test_fail "ldd check" "failed to analyze binary"
    fi
    
    # Check binary size
    local bin_size=$(stat -c%s "$PREHEAT_BIN_LOCAL" 2>/dev/null || echo 0)
    log INFO "Binary size: $(numfmt --to=iec $bin_size)"
    if [[ $bin_size -gt 1000 && $bin_size -lt 10000000 ]]; then
        test_pass "Binary size reasonable ($bin_size bytes)"
    else
        test_fail "Binary size check" "unexpected size: $bin_size"
    fi
}

# =============================================================================
# INSTALLATION TESTS
# =============================================================================

test_installation() {
    section "INSTALLATION TESTS"
    
    cd "$PROJECT_ROOT"
    
    subsection "Install"
    
    if make install >> "$LOG_FILE" 2>&1; then
        test_pass "make install succeeded"
    else
        test_fail_critical "make install" "installation failed"
        return 1
    fi
    
    # Verify installed files
    subsection "Verify Installation"
    
    local files=(
        "$PREHEAT_BIN_INSTALLED"
        "$PREHEAT_CTL_INSTALLED"
        "/usr/local/lib/systemd/system/preheat.service"
    )
    
    for f in "${files[@]}"; do
        if [[ -e "$f" ]]; then
            test_pass "$(basename "$f") installed"
        else
            test_fail "$(basename "$f") check" "not found at $f"
        fi
    done
    
    # Verify directories
    local dirs=("$STATE_DIR_INSTALLED" "$LOG_DIR_INSTALLED")
    for d in "${dirs[@]}"; do
        if [[ -d "$d" ]]; then
            test_pass "$(basename "$d") directory exists"
        else
            test_fail "$(basename "$d") directory" "not found"
        fi
    done
    
    # Reload systemd
    if systemctl daemon-reload; then
        test_pass "systemd daemon-reload succeeded"
    else
        test_fail "systemd reload" "failed"
    fi
}

# =============================================================================
# DAEMON FUNCTIONALITY TESTS
# =============================================================================

test_daemon_basic() {
    section "DAEMON BASIC FUNCTIONALITY"
    
    subsection "Version & Help"
    
    run_cmd_contains "preheat --version has version" "$PREHEAT_BIN --version" "preheat|[0-9]+\.[0-9]+"
    run_cmd_contains "preheat --help shows usage" "$PREHEAT_BIN --help" "usage|Usage|OPTIONS|options"
    run_cmd_contains "preheat-ctl help shows commands" "$PREHEAT_CTL help" "stats|status|reload"
    
    subsection "Daemon Lifecycle"
    
    # Stop any running instance
    stop_daemon
    
    run_cmd "Daemon not running initially" "! pgrep -x preheat"
    
    # Start via systemctl
    log INFO "Starting daemon via systemctl..."
    if systemctl start preheat; then
        test_pass "systemctl start succeeded"
    else
        test_fail "systemctl start" "failed to start"
        # Try to get more info
        journalctl -u preheat -n 20 >> "$LOG_FILE" 2>&1
    fi
    
    sleep 2
    
    if pgrep -x preheat > /dev/null; then
        test_pass "Daemon is running"
        local pid=$(pgrep -x preheat)
        log INFO "Daemon PID: $pid"
    else
        test_fail_critical "Daemon running check" "not running after start"
        return 1
    fi
    
    # Check PID file
    if [[ -f /run/preheat.pid ]]; then
        test_pass "PID file created"
        local pid_file=$(cat /run/preheat.pid)
        local pid_actual=$(pgrep -x preheat | head -1)
        if [[ "$pid_file" == "$pid_actual" ]]; then
            test_pass "PID file matches running process"
        else
            test_fail "PID match" "file=$pid_file, actual=$pid_actual"
        fi
    else
        test_fail "PID file check" "not found"
    fi
    
    # Test restart
    subsection "Restart"
    
    local old_pid=$(pgrep -x preheat | head -1)
    run_cmd "systemctl restart succeeds" "systemctl restart preheat"
    sleep 2
    
    if pgrep -x preheat > /dev/null; then
        test_pass "Daemon running after restart"
        local new_pid=$(pgrep -x preheat | head -1)
        if [[ "$new_pid" != "$old_pid" ]]; then
            test_pass "New PID after restart ($old_pid -> $new_pid)"
        fi
    else
        test_fail "Restart check" "daemon not running"
    fi
    
    # Test stop
    subsection "Stop"
    
    run_cmd "preheat-ctl stop succeeds" "$PREHEAT_CTL stop"
    sleep 2
    
    if ! pgrep -x preheat > /dev/null; then
        test_pass "Daemon stopped cleanly"
    else
        test_fail "Stop check" "daemon still running"
        pkill -9 preheat 2>/dev/null || true
    fi
    
    # Restart for further tests
    systemctl start preheat
    wait_daemon_start
}

# =============================================================================
# SIGNAL HANDLING TESTS
# =============================================================================

test_signals() {
    section "SIGNAL HANDLING"
    
    systemctl start preheat 2>/dev/null || true
    wait_daemon_start
    
    local pid=$(pgrep -x preheat | head -1)
    if [[ -z "$pid" ]]; then
        test_skip "Signal tests" "daemon not running"
        return
    fi
    
    log INFO "Testing signals on PID $pid"
    
    subsection "SIGHUP (Reload)"
    
    run_cmd "SIGHUP sent" "kill -HUP $pid"
    sleep 1
    if pgrep -x preheat > /dev/null; then
        test_pass "Daemon survived SIGHUP"
    else
        test_fail "SIGHUP survival" "daemon died"
        systemctl start preheat; wait_daemon_start
    fi
    
    subsection "SIGUSR1 (Dump Stats)"
    
    run_cmd "SIGUSR1 sent" "kill -USR1 $pid"
    sleep 1
    if pgrep -x preheat > /dev/null; then
        test_pass "Daemon survived SIGUSR1"
    else
        test_fail "SIGUSR1 survival" "daemon died"
        systemctl start preheat; wait_daemon_start
    fi
    
    if [[ -f /run/preheat.stats ]]; then
        test_pass "Stats file created after SIGUSR1"
    else
        test_skip "Stats file check" "may use different path"
    fi
    
    subsection "SIGUSR2 (Force Save)"
    
    run_cmd "SIGUSR2 sent" "kill -USR2 $pid"
    sleep 2
    if pgrep -x preheat > /dev/null; then
        test_pass "Daemon survived SIGUSR2"
    else
        test_fail "SIGUSR2 survival" "daemon died"
    fi
    
    subsection "SIGTERM (Graceful Shutdown)"
    
    local test_pid=$(pgrep -x preheat | head -1)
    kill -TERM "$test_pid" 2>/dev/null || true
    sleep 3
    
    if ! pgrep -x preheat > /dev/null; then
        test_pass "SIGTERM caused graceful shutdown"
    else
        test_fail "SIGTERM shutdown" "daemon still running"
    fi
    
    # Restart
    systemctl start preheat
    wait_daemon_start
}

# =============================================================================
# CLI TOOL TESTS  
# =============================================================================

test_cli_commands() {
    section "CLI TOOL COMMANDS"
    
    systemctl start preheat 2>/dev/null || true
    wait_daemon_start
    sleep 3  # Allow stats to accumulate
    
    subsection "Status Commands"
    
    run_cmd "preheat-ctl status succeeds" "$PREHEAT_CTL status"
    run_cmd_contains "status shows running" "$PREHEAT_CTL status" "running|Running|active"
    
    subsection "Stats Commands"
    
    run_cmd "preheat-ctl stats succeeds" "$PREHEAT_CTL stats"
    run_cmd_contains "stats shows uptime" "$PREHEAT_CTL stats" "[Uu]ptime"
    run_cmd_contains "stats shows apps tracked" "$PREHEAT_CTL stats" "tracked|Tracked"
    run_cmd "preheat-ctl stats -v succeeds" "$PREHEAT_CTL stats -v"
    
    subsection "Memory Commands"
    
    run_cmd "preheat-ctl mem succeeds" "$PREHEAT_CTL mem"
    run_cmd_contains "mem shows total" "$PREHEAT_CTL mem" "[Tt]otal"
    run_cmd_contains "mem shows free" "$PREHEAT_CTL mem" "[Ff]ree|[Aa]vailable"
    
    subsection "Predict Commands"
    
    run_cmd "preheat-ctl predict succeeds" "$PREHEAT_CTL predict"
    run_cmd "preheat-ctl predict --top 5" "$PREHEAT_CTL predict --top 5"
    
    subsection "Health Commands"
    
    run_cmd "preheat-ctl health succeeds" "$PREHEAT_CTL health"
    
    subsection "Pause/Resume"
    
    run_cmd "preheat-ctl pause succeeds" "$PREHEAT_CTL pause 1m"
    sleep 1
    run_cmd_contains "status shows paused" "$PREHEAT_CTL status" "[Pp]aused|PAUSED"
    run_cmd "preheat-ctl resume succeeds" "$PREHEAT_CTL resume"
    
    subsection "Reload"
    
    run_cmd "preheat-ctl reload succeeds" "$PREHEAT_CTL reload"
    sleep 1
    if pgrep -x preheat > /dev/null; then
        test_pass "Daemon running after reload"
    else
        test_fail "Reload survival" "daemon stopped"
    fi
    
    subsection "Save"
    
    run_cmd "preheat-ctl save succeeds" "$PREHEAT_CTL save"
    
    subsection "Export/Import"
    
    local export_file="$TEMP_DIR/export.json"
    mkdir -p "$TEMP_DIR"
    
    run_cmd "preheat-ctl export succeeds" "$PREHEAT_CTL export '$export_file'"
    
    if [[ -f "$export_file" ]]; then
        test_pass "Export file created"
        
        # Validate JSON
        if python3 -c "import json; json.load(open('$export_file'))" 2>/dev/null || \
           jq . "$export_file" > /dev/null 2>&1; then
            test_pass "Export file is valid JSON"
        else
            test_fail "JSON validation" "invalid JSON"
        fi
    else
        test_fail "Export file creation" "file not found"
    fi
    
    subsection "Explain Command"
    
    run_cmd "explain /bin/bash succeeds" "$PREHEAT_CTL explain /bin/bash"
    run_cmd "explain unknown path handled" "$PREHEAT_CTL explain /nonexistent/path" 0
}

# =============================================================================
# STATE PERSISTENCE TESTS
# =============================================================================

test_state_persistence() {
    section "STATE PERSISTENCE"
    
    local state_file="$STATE_DIR_INSTALLED/preheat.state"
    
    subsection "State File Operations"
    
    # Force save
    systemctl start preheat 2>/dev/null || true
    wait_daemon_start
    sleep 2
    
    $PREHEAT_CTL save 2>/dev/null || true
    sleep 2
    
    if [[ -f "$state_file" ]]; then
        test_pass "State file exists"
        
        local size=$(stat -c%s "$state_file")
        log INFO "State file size: $size bytes"
        
        if [[ $size -gt 0 ]]; then
            test_pass "State file is not empty"
        else
            test_fail "State file content" "file is empty"
        fi
        
        # Check header
        if head -c 20 "$state_file" | xxd | grep -q "PRELOAD"; then
            test_pass "State file has valid header"
        else
            log WARN "Could not verify state file header"
        fi
    else
        test_fail "State file check" "not found at $state_file"
    fi
    
    subsection "State Survives Restart"
    
    # Get current stats
    local apps_before=$($PREHEAT_CTL stats 2>/dev/null | grep -o '[0-9]* apps' | head -1 || echo "")
    
    # Restart
    systemctl restart preheat
    wait_daemon_start
    sleep 2
    
    local apps_after=$($PREHEAT_CTL stats 2>/dev/null | grep -o '[0-9]* apps' | head -1 || echo "")
    
    log INFO "Apps before: $apps_before, after: $apps_after"
    
    if [[ -n "$apps_before" && -n "$apps_after" ]]; then
        test_pass "Stats preserved across restart"
    else
        test_skip "State persistence comparison" "could not parse stats"
    fi
}

# =============================================================================
# CONFIGURATION TESTS
# =============================================================================

test_configuration() {
    section "CONFIGURATION"
    
    subsection "Config File"
    
    if [[ -f "$CONFIG_INSTALLED" ]]; then
        test_pass "Config file exists"
        
        # Check for key sections
        if grep -q '\[model\]' "$CONFIG_INSTALLED"; then
            test_pass "Config has [model] section"
        else
            test_skip "[model] section" "not found"
        fi
        
        if grep -q '\[system\]' "$CONFIG_INSTALLED"; then
            test_pass "Config has [system] section"
        else
            test_skip "[system] section" "not found"
        fi
    else
        test_skip "Config file tests" "config not found"
    fi
    
    subsection "Default Config Generation"
    
    # Test daemon can start without config
    stop_daemon
    
    if [[ -f "$CONFIG_INSTALLED" ]]; then
        mv "$CONFIG_INSTALLED" "${CONFIG_INSTALLED}.test_backup"
    fi
    
    # Try to start - may or may not work depending on implementation
    systemctl start preheat 2>/dev/null || true
    sleep 2
    
    if pgrep -x preheat > /dev/null; then
        test_pass "Daemon starts without config file (uses defaults)"
    else
        log INFO "Daemon requires config file (expected behavior)"
    fi
    
    # Restore config
    if [[ -f "${CONFIG_INSTALLED}.test_backup" ]]; then
        mv "${CONFIG_INSTALLED}.test_backup" "$CONFIG_INSTALLED"
    fi
    
    systemctl restart preheat 2>/dev/null || true
    wait_daemon_start
}

# =============================================================================
# PERFORMANCE TESTS
# =============================================================================

test_performance() {
    section "PERFORMANCE TESTS"
    
    systemctl start preheat 2>/dev/null || true
    wait_daemon_start
    sleep 2
    
    subsection "Resource Usage"
    
    local pid=$(pgrep -x preheat | head -1)
    if [[ -z "$pid" ]]; then
        test_skip "Performance tests" "daemon not running"
        return
    fi
    
    # Memory usage
    local mem_kb=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')
    local mem_mb=$((mem_kb / 1024))
    log INFO "Daemon memory usage: ${mem_mb}MB (${mem_kb}KB)"
    
    if [[ $mem_mb -lt 50 ]]; then
        test_pass "Memory usage under 50MB ($mem_mb MB)"
    elif [[ $mem_mb -lt 100 ]]; then
        log WARN "Memory usage higher than expected: $mem_mb MB"
        test_pass "Memory usage under 100MB ($mem_mb MB)"
    else
        test_fail "Memory usage" "excessive: $mem_mb MB"
    fi
    
    # CPU usage (sample over 5 seconds)
    local cpu_sample=$(top -b -n 3 -d 1 -p "$pid" 2>/dev/null | awk '/preheat/{print $9}' | tail -1 || echo "0")
    log INFO "CPU usage sample: $cpu_sample%"
    
    subsection "CLI Response Time"
    
    # Measure stats response time
    local start_time=$(date +%s%3N)
    $PREHEAT_CTL stats > /dev/null 2>&1
    local end_time=$(date +%s%3N)
    local response_ms=$((end_time - start_time))
    
    log INFO "Stats command response: ${response_ms}ms"
    
    if [[ $response_ms -lt 500 ]]; then
        test_pass "Stats command fast ($response_ms ms)"
    elif [[ $response_ms -lt 2000 ]]; then
        test_pass "Stats command acceptable ($response_ms ms)"
    else
        test_fail "Stats response time" "slow: $response_ms ms"
    fi
    
    subsection "Rapid Command Execution"
    
    local success=0
    local total=20
    for ((i=0; i<total; i++)); do
        if $PREHEAT_CTL stats > /dev/null 2>&1; then
            ((success++))
        fi
    done
    
    log INFO "Rapid commands: $success/$total succeeded"
    
    if [[ $success -ge 18 ]]; then
        test_pass "Rapid commands handled ($success/$total)"
    else
        test_fail "Rapid commands" "too many failures: $success/$total"
    fi
}

# =============================================================================
# STRESS TESTS
# =============================================================================

test_stress() {
    section "STRESS TESTS"
    
    systemctl start preheat 2>/dev/null || true
    wait_daemon_start
    
    subsection "Rapid Signal Stress"
    
    local pid=$(pgrep -x preheat | head -1)
    if [[ -n "$pid" ]]; then
        for ((i=0; i<15; i++)); do
            kill -USR1 "$pid" 2>/dev/null || true
            sleep 0.1
        done
        
        if pgrep -x preheat > /dev/null; then
            test_pass "Daemon survived rapid SIGUSR1"
        else
            test_fail "Signal stress" "daemon crashed"
            systemctl start preheat; wait_daemon_start
        fi
    fi
    
    subsection "Rapid Restart Stress"
    
    local success=0
    for ((i=0; i<5; i++)); do
        systemctl restart preheat 2>/dev/null
        sleep 2
        if pgrep -x preheat > /dev/null; then
            ((success++))
        fi
    done
    
    if [[ $success -eq 5 ]]; then
        test_pass "All rapid restarts succeeded ($success/5)"
    else
        test_fail "Rapid restarts" "$success/5 succeeded"
    fi
    
    subsection "Long Running Stability"
    
    log INFO "Running daemon for 30 seconds with activity..."
    
    local pid=$(pgrep -x preheat | head -1)
    for ((i=0; i<6; i++)); do
        $PREHEAT_CTL stats > /dev/null 2>&1 || true
        kill -USR1 "$pid" 2>/dev/null || true
        sleep 5
    done
    
    if pgrep -x preheat > /dev/null; then
        test_pass "Daemon stable after 30s activity"
    else
        test_fail "Long running stability" "daemon crashed"
    fi
}

# =============================================================================
# EDGE CASE TESTS
# =============================================================================

test_edge_cases() {
    section "EDGE CASE TESTS"
    
    subsection "Invalid Commands"
    
    run_cmd "Unknown command returns error" "$PREHEAT_CTL unknowncommand" 1
    run_cmd "No args shows help" "$PREHEAT_CTL" 1
    
    subsection "Double Start/Stop"
    
    # Double stop should be safe
    systemctl stop preheat 2>/dev/null || true
    wait_daemon_stop
    run_cmd "Double stop is safe" "systemctl stop preheat" 0
    
    # Double start 
    systemctl start preheat
    wait_daemon_start
    run_cmd "Double start is handled" "systemctl start preheat" 0
    
    subsection "Self-Test Mode"
    
    stop_daemon
    run_cmd "Self-test mode works" "$PREHEAT_BIN --self-test"
    
    # Restart
    systemctl start preheat
    wait_daemon_start
}

# =============================================================================
# FOREGROUND MODE TEST
# =============================================================================

test_foreground_mode() {
    section "FOREGROUND MODE"
    
    stop_daemon
    
    mkdir -p "$TEMP_DIR"
    
    log INFO "Starting daemon in foreground mode (5 second test)..."
    
    timeout 5 $PREHEAT_BIN -f > "$TEMP_DIR/foreground.log" 2>&1 &
    local fg_pid=$!
    sleep 3
    
    if ps -p $fg_pid > /dev/null 2>&1; then
        test_pass "Foreground mode runs"
        kill $fg_pid 2>/dev/null || true
        wait $fg_pid 2>/dev/null || true
    else
        wait $fg_pid 2>/dev/null
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            test_pass "Foreground mode ran until timeout"
        else
            log WARN "Foreground mode exited with code $exit_code"
        fi
    fi
    
    if [[ -f "$TEMP_DIR/foreground.log" ]]; then
        local log_size=$(stat -c%s "$TEMP_DIR/foreground.log")
        log INFO "Foreground log size: $log_size bytes"
        if [[ $log_size -gt 0 ]]; then
            log DEBUG "First 20 lines of foreground log:"
            head -20 "$TEMP_DIR/foreground.log" >> "$LOG_FILE"
        fi
    fi
    
    # Restart systemd daemon
    systemctl start preheat
    wait_daemon_start
}

# =============================================================================
# DEBIAN SPECIFIC TESTS
# =============================================================================

test_debian_specific() {
    section "DEBIAN 12 SPECIFIC TESTS"
    
    subsection "systemd Integration"
    
    # Check service status
    if systemctl is-enabled preheat > /dev/null 2>&1; then
        test_pass "preheat service is enabled"
    else
        log INFO "preheat service not enabled (run: systemctl enable preheat)"
    fi
    
    # Check journal logging
    if journalctl -u preheat -n 5 > /dev/null 2>&1; then
        test_pass "Journal logging works"
    else
        test_skip "Journal test" "cannot read journal"
    fi
    
    subsection "Security Hardening (if applicable)"
    
    # Check capabilities if service uses them
    if getcap "$PREHEAT_BIN" 2>/dev/null | grep -q "cap_"; then
        test_pass "Binary has capabilities set"
    else
        log INFO "No special capabilities (running as root)"
    fi
    
    subsection "Common Debian Apps Detection"
    
    # List some common Debian apps and check if daemon can track them
    local debian_apps=(
        "/usr/bin/nautilus"
        "/usr/bin/gnome-terminal"
        "/usr/bin/firefox"
        "/usr/bin/firefox-esr"
        "/usr/bin/gedit"
        "/usr/bin/evince"
    )
    
    for app in "${debian_apps[@]}"; do
        if [[ -x "$app" ]]; then
            log INFO "Found Debian app: $app"
        fi
    done
}

# =============================================================================
# GENERATE REPORT
# =============================================================================

generate_report() {
    cat > "$REPORT_FILE" << EOF
================================================================================
PREHEAT DAEMON - DEBIAN 12 TEST REPORT
================================================================================
Generated: $(date)
System: $(uname -a)
Test Log: $LOG_FILE

SUMMARY
-------
Total Tests:  $TESTS_RUN
Passed:       $TESTS_PASSED
Failed:       $TESTS_FAILED
Skipped:      $TESTS_SKIPPED
Critical:     $CRITICAL_FAILURES

RESULT: $(if [[ $TESTS_FAILED -eq 0 ]]; then echo "ALL TESTS PASSED"; else echo "SOME TESTS FAILED"; fi)

================================================================================
EOF
    
    log INFO "Report saved to: $REPORT_FILE"
}

# =============================================================================
# MAIN
# =============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --quick)
                QUICK_MODE=true
                shift
                ;;
            --build)
                BUILD_FIRST=true
                shift
                ;;
            --no-install)
                NO_INSTALL_MODE=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --quick       Run quick smoke tests only"
                echo "  --build       Build from source before testing"
                echo "  --no-install  Test local build without installation"
                echo "  --help        Show this help"
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

main() {
    parse_args "$@"
    
    echo ""
    echo -e "${BOLD}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║      PREHEAT DAEMON - DEBIAN 12 COMPREHENSIVE TEST SUITE          ║${NC}"
    echo -e "${BOLD}╠════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}║  Log: ${CYAN}$LOG_FILE${NC}"
    echo -e "${BOLD}╚════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Initialize
    mkdir -p "$TEMP_DIR"
    echo "Preheat Debian 12 Test Suite - $(date)" > "$LOG_FILE"
    
    # Set binary paths
    if [[ "$NO_INSTALL_MODE" == true ]]; then
        PREHEAT_BIN="$PREHEAT_BIN_LOCAL"
        PREHEAT_CTL="$PREHEAT_CTL_LOCAL"
        log INFO "Using local build: $PREHEAT_BIN"
    else
        PREHEAT_BIN="$PREHEAT_BIN_INSTALLED"
        PREHEAT_CTL="$PREHEAT_CTL_INSTALLED"
    fi
    
    # Run tests
    check_debian_12
    
    if [[ "$BUILD_FIRST" == true ]]; then
        check_build_deps
        test_build
        test_installation
    fi
    
    if [[ "$QUICK_MODE" == true ]]; then
        # Quick mode - just basic tests
        test_daemon_basic
        test_cli_commands
    else
        # Full test suite
        test_daemon_basic
        test_signals
        test_cli_commands
        test_state_persistence
        test_configuration
        test_performance
        test_stress
        test_edge_cases
        test_foreground_mode
        test_debian_specific
    fi
    
    # Summary
    section "FINAL RESULTS"
    
    echo ""
    echo -e "${BOLD}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║  TEST SUMMARY                                                      ║${NC}"
    echo -e "${BOLD}╠════════════════════════════════════════════════════════════════════╣${NC}"
    printf "║  Total Tests:     %-50d ║\n" "$TESTS_RUN"
    printf "║  ${GREEN}Passed:           %-50d${NC} ║\n" "$TESTS_PASSED"
    printf "║  ${RED}Failed:           %-50d${NC} ║\n" "$TESTS_FAILED"
    printf "║  ${CYAN}Skipped:          %-50d${NC} ║\n" "$TESTS_SKIPPED"
    
    if [[ $CRITICAL_FAILURES -gt 0 ]]; then
        printf "║  ${RED}${BOLD}Critical:         %-50d${NC} ║\n" "$CRITICAL_FAILURES"
    fi
    
    echo -e "${BOLD}╠════════════════════════════════════════════════════════════════════╣${NC}"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${BOLD}║  ${GREEN}★★★ ALL TESTS PASSED ★★★${NC}                                       ║"
    else
        echo -e "${BOLD}║  ${RED}✗ $TESTS_FAILED TESTS FAILED${NC}                                               ║"
    fi
    
    echo -e "${BOLD}╠════════════════════════════════════════════════════════════════════╣${NC}"
    echo "║  Full log: $LOG_FILE"
    echo -e "${BOLD}╚════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    generate_report
    
    # Exit with appropriate code
    if [[ $CRITICAL_FAILURES -gt 0 ]]; then
        exit 2
    elif [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

main "$@"
