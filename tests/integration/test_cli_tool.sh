#!/bin/bash
# Test script for preheat-ctl

set -e

echo "========================================="
echo "Testing preheat-ctl"
echo "========================================="
echo ""

# Cleanup
sudo killall preheat 2>/dev/null || true
sleep 1
sudo rm -f /var/run/preheat.pid

# Test 1: Help command
echo "TEST 1: Help command"
./tools/preheat-ctl help | head -5
echo ""

# Test 2: Status when not running
echo "TEST 2: Status check (daemon not running)"
if ./tools/preheat-ctl status 2>&1 | grep -q "not found"; then
    echo "✓ Correctly reports daemon not running"
else
    echo "✗ Status check failed"
fi
echo ""

# Test 3: Start daemon
echo "TEST 3: Starting daemon..."
sudo ./src/preheat -c config/preheat.conf.default &
sleep 2

# Test 4: Status when running
echo "TEST 4: Status check (daemon running)"
if sudo ./tools/preheat-ctl status; then
    echo "✓ Status check passed"
else
    echo "✗ Status check failed"
fi
echo ""

# Test 5: Dump command
echo "TEST 5: Dump state"
if sudo ./tools/preheat-ctl dump; then
    echo "✓ Dump command sent"
else
    echo "✗ Dump command failed"
fi
echo ""

# Test 6: Save command
echo "TEST 6: Save state"
if sudo ./tools/preheat-ctl save; then
    echo "✓ Save command sent"
else
    echo "✗ Save command failed"
fi
echo ""

# Test 7: Reload command
echo "TEST 7: Reload config"
if sudo ./tools/preheat-ctl reload; then
    echo "✓ Reload command sent"
else
    echo "✗ Reload command failed"
fi
echo ""

# Test 8: Stop command
echo "TEST 8: Stop daemon"
if sudo ./tools/preheat-ctl stop; then
    echo "✓ Stop command successful"
else
    echo "✗ Stop command failed"
fi
echo ""

# Test 9: Verify stopped
echo "TEST 9: Verify daemon stopped"
sleep 1
if sudo ./tools/preheat-ctl status 2>&1 | grep -q "not found\|not running"; then
    echo "✓ Daemon properly stopped"
else
    echo "✗ Daemon still running"
    sudo killall -9 preheat 2>/dev/null || true
fi
echo ""

echo "========================================="
echo "CLI Tool Tests Complete!"
echo "========================================="
