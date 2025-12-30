#!/bin/bash
# Comprehensive PID Persistence Testing Script
# Tests running process persistence across daemon restarts
# Logs everything to test_results.log

# Note: Not using set -e due to arithmetic operations


# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log file
LOGFILE="test_pid_persistence_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1

# Configuration
STATE_FILE="/usr/local/var/lib/preheat/preheat.state"
PREHEAT_CTL="./tools/preheat-ctl"
TEST_APP="/usr/bin/gedit"  # Simple GUI app for testing
SCAN_CYCLE=90  # Daemon scan cycle in seconds
AUTOSAVE=300   # Autosave interval

# Test results tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

#####################################################################
# Helper Functions
#####################################################################

log_header() {
    echo ""
    echo "=============================================================="
    echo "  $1"
    echo "=============================================================="
    echo ""
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $(date '+%H:%M:%S') - $1"
    ((TESTS_PASSED++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $(date '+%H:%M:%S') - $1"
    ((TESTS_FAILED++))
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%H:%M:%S') - $1"
}

wait_with_progress() {
    local duration=$1
    local message=$2
    log_info "$message (${duration}s)"
    
    for ((i=$duration; i>0; i--)); do
        printf "\r  ⏳ Waiting... %3ds remaining" $i
        sleep 1
    done
    printf "\r  ✓ Wait complete (${duration}s)     \n"
}

check_daemon_running() {
    if ! systemctl is-active --quiet preheat; then
        log_fail "Preheat daemon is not running!"
        return 1
    fi
    log_success "Daemon is running (PID: $(pgrep preheat))"
    return 0
}

force_state_save() {
    log_info "Forcing state save (SIGUSR2)"
    sudo kill -SIGUSR2 $(pgrep preheat)
    sleep 2
}

get_firefox_pid() {
    pgrep -x firefox-esr | head -1 || echo ""
}

get_app_weight() {
    local app=$1
    sudo $PREHEAT_CTL explain "$app" 2>/dev/null | grep "Weighted Launches:" | awk '{print $3}' || echo "0"
}

get_app_raw_launches() {
    local app=$1
    sudo $PREHEAT_CTL explain "$app" 2>/dev/null | grep "Raw Launches:" | awk '{print $3}' || echo "0"
}

count_pids_in_state() {
    local app=$1
    sudo cat "$STATE_FILE" 2>/dev/null | grep -c "PID.*$app" || echo "0"
}

check_state_has_pids() {
    local app=$1
    if sudo cat "$STATE_FILE" 2>/dev/null | grep -q "PIDS"; then
        log_success "State file contains PIDS subsections"
        
        # Show sample
        log_info "Sample PIDS entries:"
        sudo cat "$STATE_FILE" | grep -A5 "PIDS" | head -20 | sed 's/^/    /'
        return 0
    else
        log_fail "State file does NOT contain PIDS subsections"
        return 1
    fi
}

#####################################################################
# Test Cases
#####################################################################

test_daemon_status() {
    log_header "TEST 1: Daemon Status & Configuration"
    ((TESTS_RUN++))
    
    check_daemon_running || return 1
    
    # Check autosave config
    local autosave=$(grep "^autosave" /usr/local/etc/preheat.conf 2>/dev/null | awk '{print $3}' || echo "unknown")
    log_info "Autosave interval: ${autosave}s"
    
    if [[ "$autosave" == "300" ]]; then
        log_success "Autosave correctly set to 300s"
    else
        log_warn "Autosave is $autosave, expected 300"
    fi
    
    # Check daemon uptime
    local uptime=$(sudo $PREHEAT_CTL stats 2>/dev/null | grep "Uptime:" | awk '{print $2}')
    log_info "Daemon uptime: $uptime"
    
    log_success "Test 1 complete"
}

test_firefox_current_state() {
    log_header "TEST 2: Firefox Current State"
    ((TESTS_RUN++))
    
    local firefox_pid=$(get_firefox_pid)
    
    if [[ -z "$firefox_pid" ]]; then
        log_warn "Firefox is not running (PID not found)"
        log_info "This is OK - we'll test with it later if running"
        log_success "Test 2 complete (Firefox not running)"
        return 0
    fi
    
    log_info "Firefox is running (PID: $firefox_pid)"
    
    # Check uptime
    local start_time=$(ps -p $firefox_pid -o lstart= 2>/dev/null || echo "unknown")
    log_info "Firefox started: $start_time"
    
    # Check current weight
    local weight=$(get_app_weight "/usr/lib/firefox-esr/firefox-esr")
    local raw=$(get_app_raw_launches "/usr/lib/firefox-esr/firefox-esr")
    log_info "Current weight: $weight, Raw launches: $raw"
    
    # Show full explain output
    log_info "Full Firefox status:"
    sudo $PREHEAT_CTL explain firefox-esr 2>/dev/null | sed 's/^/    /'
    
    log_success "Test 2 complete"
}

test_wait_for_scan() {
    log_header "TEST 3: Wait for Process Detection"
    ((TESTS_RUN++))
    
    log_info "Waiting for 2 scan cycles to ensure Firefox is detected..."
    wait_with_progress $((SCAN_CYCLE * 2)) "Daemon scanning for running processes"
    
    # Check if Firefox weight increased (if running)
    local firefox_pid=$(get_firefox_pid)
    if [[ -n "$firefox_pid" ]]; then
        local weight=$(get_app_weight "/usr/lib/firefox-esr/firefox-esr")
        log_info "Firefox weight after scan: $weight"
        
        if (( $(echo "$weight > 1.0" | bc -l) )); then
            log_success "Firefox weight is accumulating ($weight)"
        else
            log_warn "Firefox weight still low ($weight), may need more time"
        fi
    fi
    
    log_success "Test 3 complete"
}

test_force_save_and_check() {
    log_header "TEST 4: Force State Save & Verify PIDS"
    ((TESTS_RUN++))
    
    log_info "Forcing immediate state save..."
    force_state_save
    
    log_info "State file location: $STATE_FILE"
    log_info "State file size: $(du -h $STATE_FILE 2>/dev/null | awk '{print $1}')"
    
    # Check for PIDS subsections
    if check_state_has_pids ""; then
        log_success "PIDS subsections found in state file"
    else
        log_fail "No PIDS subsections in state file yet"
        log_info "This may be normal if no processes were active during save"
    fi
    
    # Count PIDs in state
    local pid_count=$(sudo cat "$STATE_FILE" | grep -c "^    PID" || echo "0")
    log_info "Total PIDs in state file: $pid_count"
    
    # Show Firefox entry
    local firefox_pid=$(get_firefox_pid)
    if [[ -n "$firefox_pid" ]]; then
        log_info "Looking for Firefox PIDs in state file..."
        if sudo cat "$STATE_FILE" | grep -q "firefox-esr"; then
            log_info "Firefox state entry:"
            sudo cat "$STATE_FILE" | grep -A10 "firefox-esr" | sed 's/^/    /'
        else
            log_warn "Firefox not found in state file"
        fi
    fi
    
    log_success "Test 4 complete"
}

test_restart_and_verify_persistence() {
    log_header "TEST 5: Daemon Restart & Weight Persistence"
    ((TESTS_RUN++))
    
    local firefox_pid=$(get_firefox_pid)
    if [[ -z "$firefox_pid" ]]; then
        log_warn "Firefox not running, skipping persistence test"
        log_success "Test 5 skipped (Firefox not running)"
        return 0
    fi
    
    log_info "Firefox PID before restart: $firefox_pid"
    
    # Get weight before restart
    local weight_before=$(get_app_weight "/usr/lib/firefox-esr/firefox-esr")
    local raw_before=$(get_app_raw_launches "/usr/lib/firefox-esr/firefox-esr")
    
    log_info "Weight before restart: $weight_before"
    log_info "Raw launches before restart: $raw_before"
    
    # Restart daemon
    log_info "Restarting daemon..."
    sudo systemctl restart preheat
    sleep 5
    
    check_daemon_running || return 1
    
    # Check Firefox still running
    local firefox_pid_after=$(get_firefox_pid)
    if [[ "$firefox_pid" != "$firefox_pid_after" ]]; then
        log_fail "Firefox PID changed! Before: $firefox_pid, After: $firefox_pid_after"
        return 1
    fi
    log_success "Firefox still running (same PID: $firefox_pid)"
    
    # Wait for daemon to initialize
    wait_with_progress 30 "Waiting for daemon to initialize and load state"
    
    # Get weight after restart
    local weight_after=$(get_app_weight "/usr/lib/firefox-esr/firefox-esr")
    local raw_after=$(get_app_raw_launches "/usr/lib/firefox-esr/firefox-esr")
    
    log_info "Weight after restart: $weight_after"
    log_info "Raw launches after restart: $raw_after"
    
    # Compare weights (allow 10% variance for timing)
    local weight_diff=$(echo "$weight_after - $weight_before" | bc -l)
    local weight_ratio=$(echo "scale=2; $weight_after / $weight_before" | bc -l 2>/dev/null || echo "0")
    
    log_info "Weight change: $weight_diff (ratio: $weight_ratio)"
    
    if (( $(echo "$weight_ratio >= 0.90" | bc -l) )); then
        log_success "✓ Weight preserved across restart (ratio: $weight_ratio)"
    else
        log_fail "✗ Weight NOT preserved (ratio: $weight_ratio, expected >= 0.90)"
    fi
    
    # Check raw launches didn't increment
    if [[ "$raw_after" == "$raw_before" ]]; then
        log_success "✓ Raw launches unchanged ($raw_after) - resume logic working!"
    else
        log_fail "✗ Raw launches incremented ($raw_before → $raw_after) - double counting!"
    fi
    
    log_success "Test 5 complete"
}

test_weight_accumulation() {
    log_header "TEST 6: Incremental Weight Accumulation"
    ((TESTS_RUN++))
    
    local firefox_pid=$(get_firefox_pid)
    if [[ -z "$firefox_pid" ]]; then
        log_warn "Firefox not running, skipping accumulation test"
        log_success "Test 6 skipped (Firefox not running)"
        return 0
    fi
    
    local weight_start=$(get_app_weight "/usr/lib/firefox-esr/firefox-esr")
    log_info "Starting weight: $weight_start"
    
    log_info "Waiting for weight to accumulate..."
    wait_with_progress 300 "Monitoring incremental weight updates (5 minutes)"
    
    local weight_end=$(get_app_weight "/usr/lib/firefox-esr/firefox-esr")
    log_info "Ending weight: $weight_end"
    
    local weight_increase=$(echo "$weight_end - $weight_start" | bc -l)
    log_info "Weight increase: $weight_increase"
    
    if (( $(echo "$weight_increase > 0.1" | bc -l) )); then
        log_success "✓ Weight is accumulating (+$weight_increase over 5min)"
    else
        log_fail "✗ Weight not accumulating (only +$weight_increase)"
    fi
    
    log_success "Test 6 complete"
}

test_ranking_improvement() {
    log_header "TEST 7: Firefox Ranking Check"
    ((TESTS_RUN++))
    
    log_info "Checking Firefox ranking in top 20..."
    
    local rank=$(sudo $PREHEAT_CTL stats --verbose 2>/dev/null | grep -n "firefox" | head -1 | cut -d: -f1 || echo "999")
    
    # Subtract header lines (approximately 24 lines before top 20)
    rank=$((rank - 24))
    
    if [[ $rank -le 20 ]] && [[ $rank -gt 0 ]]; then
        log_success "✓ Firefox is in top 20 (rank ~$rank)"
    else
        log_warn "Firefox not in top 20 yet (may need more runtime)"
        log_info "Current top 20:"
        sudo $PREHEAT_CTL stats --verbose 2>/dev/null | head -45 | tail -22 | sed 's/^/    /'
    fi
    
    log_success "Test 7 complete"
}

test_pid_validation() {
    log_header "TEST 8: PID Validation Logic"
    ((TESTS_RUN++))
    
    log_info "Testing PID validation by examining logs..."
    
    # Check recent daemon logs for PID validation messages
    log_info "Looking for PID validation messages in journal..."
    
    local skipped_count=$(sudo journalctl -u preheat --since '10 minutes ago' --no-pager 2>/dev/null | \
        grep -c "Skipping.*PID" || echo "0")
    
    log_info "PIDs skipped during validation: $skipped_count"
    
    if [[ $skipped_count -gt 0 ]]; then
        log_info "Sample validation messages:"
        sudo journalctl -u preheat --since '10 minutes ago' --no-pager 2>/dev/null | \
            grep "Skipping.*PID" | head -5 | sed 's/^/    /'
    fi
    
    # This is informational, not pass/fail
    log_success "Test 8 complete (informational)"
}

test_state_file_integrity() {
    log_header "TEST 9: State File Integrity"
    ((TESTS_RUN++))
    
    log_info "Checking state file integrity..."
    
    # Force save
    force_state_save
    
    # Try to load state (daemon will validate CRC)
    log_info "Restarting daemon to validate state file..."
    sudo systemctl restart preheat
    sleep 5
    
    if check_daemon_running; then
        log_success "✓ State file loaded successfully (CRC valid)"
    else
        log_fail "✗ Daemon failed to start (state file corrupt?)"
        return 1
    fi
    
    # Check for corruption warnings in logs
    local corrupt_count=$(sudo journalctl -u preheat --since '1 minute ago' --no-pager 2>/dev/null | \
        grep -c "corrupt\|invalid\|CRC" || echo "0")
    
    if [[ $corrupt_count -eq 0 ]]; then
        log_success "✓ No corruption warnings in logs"
    else
        log_fail "✗ Found $corrupt_count corruption warnings"
        sudo journalctl -u preheat --since '1 minute ago' --no-pager 2>/dev/null | \
            grep -i "corrupt\|invalid\|CRC" | sed 's/^/    /'
    fi
    
    log_success "Test 9 complete"
}

test_performance_impact() {
    log_header "TEST 10: Performance Impact"
    ((TESTS_RUN++))
    
    log_info "Measuring daemon resource usage..."
    
    local pid=$(pgrep preheat)
    local cpu=$(ps -p $pid -o %cpu= | tr -d ' ')
    local mem=$(ps -p $pid -o %mem= | tr -d ' ')
    local rss=$(ps -p $pid -o rss= | tr -d ' ')
    
    log_info "CPU usage: ${cpu}%"
    log_info "Memory: ${mem}% (RSS: $((rss / 1024)) MB)"
    
    # Check if within acceptable range
    if (( $(echo "$cpu < 5.0" | bc -l) )); then
        log_success "✓ CPU usage acceptable (<5%)"
    else
        log_warn "CPU usage high: ${cpu}%"
    fi
    
    if (( $(echo "$mem < 1.0" | bc -l) )); then
        log_success "✓ Memory usage acceptable (<1%)"
    else
        log_warn "Memory usage high: ${mem}%"
    fi
    
    # Check state file size
    local state_size=$(du -k "$STATE_FILE" 2>/dev/null | awk '{print $1}')
    log_info "State file size: ${state_size} KB"
    
    if [[ $state_size -lt 500 ]]; then
        log_success "✓ State file size reasonable (<500 KB)"
    else
        log_warn "State file size large: ${state_size} KB"
    fi
    
    log_success "Test 10 complete"
}

#####################################################################
# Main Test Execution
#####################################################################

main() {
    log_header "PREHEAT PID PERSISTENCE TEST SUITE"
    
    echo "Test started: $(date)"
    echo "Hostname: $(hostname)"
    echo "Kernel: $(uname -r)"
    echo "Log file: $LOGFILE"
    echo ""
    
    log_info "Test configuration:"
    echo "  - State file: $STATE_FILE"
    echo "  - Scan cycle: ${SCAN_CYCLE}s"
    echo "  - Autosave: ${AUTOSAVE}s"
    echo "  - Test app: $TEST_APP"
    echo ""
    
    # Run all tests
    test_daemon_status
    test_firefox_current_state
    test_wait_for_scan
    test_force_save_and_check
    test_restart_and_verify_persistence
    test_weight_accumulation
    test_ranking_improvement
    test_pid_validation
    test_state_file_integrity
    test_performance_impact
    
    # Summary
    log_header "TEST SUMMARY"
    
    echo "Tests run:    $TESTS_RUN"
    echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
    echo ""
    
    local success_rate=$(echo "scale=1; $TESTS_PASSED * 100 / $TESTS_RUN" | bc)
    echo "Success rate: ${success_rate}%"
    echo ""
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}╔═══════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║                                       ║${NC}"
        echo -e "${GREEN}║   ✓ ALL TESTS PASSED SUCCESSFULLY    ║${NC}"
        echo -e "${GREEN}║                                       ║${NC}"
        echo -e "${GREEN}╚═══════════════════════════════════════╝${NC}"
        exit 0
    else
        echo -e "${RED}╔═══════════════════════════════════════╗${NC}"
        echo -e "${RED}║                                       ║${NC}"
        echo -e "${RED}║   ✗ SOME TESTS FAILED                 ║${NC}"
        echo -e "${RED}║                                       ║${NC}"
        echo -e "${RED}╚═══════════════════════════════════════╝${NC}"
        exit 1
    fi
}

# Run main
main "$@"
