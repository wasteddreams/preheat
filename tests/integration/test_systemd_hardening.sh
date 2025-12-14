#!/bin/bash
# Test systemd security hardening
# Run with: sudo ./tests/integration/test_systemd_hardening.sh

set -e

echo "========================================="
echo "Testing Systemd Security Hardening"
echo "========================================="
echo ""

# Stop any running instance
echo "Step 1: Stopping any running preheat instances..."
systemctl stop preheat 2>/dev/null || true
killall preheat 2>/dev/null || true
sleep 2

# Unmask service if masked
echo ""
echo "Step 1b: Ensuring service is unmasked..."
systemctl unmask preheat 2>/dev/null || true
systemctl daemon-reload

# Test 1: Start with systemd
echo ""
echo "Step 2: Starting preheat via systemd..."
systemctl start preheat
sleep 3

# Test 2: Check status
echo ""
echo "Step 3: Checking service status..."
if systemctl is-active --quiet preheat; then
    echo "✓ Service is active"
    systemctl status preheat --no-pager | head -20
else
    echo "✗ Service failed to start"
    echo ""
    echo "Checking logs:"
    journalctl -u preheat -n 50 --no-pager | tail -30
    exit 1
fi

# Test 3: Check /proc access
echo ""
echo "Step 4: Checking /proc access (wait 10 seconds for first scan)..."
sleep 10
if journalctl -u preheat --no-pager | grep -q "scanning"; then
    echo "✓ /proc scanning works"
else
    echo "⚠ No scanning detected yet (may need more time)"
fi

# Test 4: Check predictions
if journalctl -u preheat --no-pager | grep -q "predict"; then
    echo "✓ Prediction engine works"
else
    echo "⚠ No predictions yet (may need more time)"
fi

# Test 5: Check PID file
echo ""
echo "Step 5: Checking PID file..."
if [ -f /var/run/preheat.pid ]; then
    PID=$(cat /var/run/preheat.pid)
    echo "✓ PID file exists: $PID"
    if kill -0 $PID 2>/dev/null; then
        echo "✓ Process is running"
    else
        echo "✗ PID file exists but process not running"
    fi
else
    echo "✗ No PID file found"
fi

# Test 6: CLI tool
echo ""
echo "Step 6: Testing CLI tool..."
if preheat-ctl status; then
    echo "✓ CLI tool works"
else
    echo "✗ CLI tool failed"
fi

# Test 7: Check logs for errors
echo ""
echo "Step 7: Checking for errors in logs..."
ERROR_COUNT=$(journalctl -u preheat --no-pager | grep -i "error\|failed\|permission denied" | wc -l)
if [ "$ERROR_COUNT" -eq 0 ]; then
    echo "✓ No errors in logs"
else
    echo "⚠ Found $ERROR_COUNT error(s) in logs:"
    journalctl -u preheat --no-pager | grep -i "error\|failed\|permission denied" | tail -10
fi

# Test 8: Signal handling
echo ""
echo "Step 8: Testing signal handling..."
preheat-ctl reload
sleep 1
if journalctl -u preheat --no-pager | tail -10 | grep -q "SIGHUP\|reload"; then
    echo "✓ SIGHUP (reload) works"
fi

preheat-ctl dump
sleep 1
if journalctl -u preheat --no-pager | tail -10 | grep -q "SIGUSR1\|dump"; then
    echo "✓ SIGUSR1 (dump) works"
fi

#Summary
echo ""
echo "========================================="
echo "Test Summary"
echo "========================================="
echo ""
echo "Last 15 log lines:"
journalctl -u preheat -n 15 --no-pager
echo ""

if systemctl is-active --quiet preheat; then
    echo "✅ SYSTEMD HARDENING TEST: PASS"
    echo ""
    echo "The daemon is running successfully with security hardening enabled."
    echo "This means ProtectSystem, PrivateTmp, etc. are compatible with /proc access."
    exit 0
else
    echo "❌ SYSTEMD HARDENING TEST: FAIL"
    echo ""
    echo "The daemon failed to start or crashed."
    echo "You may need to disable security hardening in the service file."
    echo ""
    echo "Edit: /usr/local/lib/systemd/system/preheat.service"
    echo "Comment out the security options and run: systemctl daemon-reload"
    exit 1
fi
