#!/bin/bash
# Clean Reinstall Preheat with Whitelist
# Apps: Firefox, Antigravity (Chrome/Chromium), Default Terminal

set -e

echo "🧹 Cleaning up old installation..."

# Stop and disable service
sudo systemctl stop preheat 2>/dev/null || true
sudo systemctl disable preheat 2>/dev/null || true

# Remove old installation
sudo rm -f /usr/local/sbin/preheat
sudo rm -f /usr/local/sbin/preheat-ctl
sudo rm -f /usr/local/lib/systemd/system/preheat.service
sudo rm -f /usr/local/etc/preheat.conf
sudo rm -rf /usr/local/var/lib/preheat/
sudo rm -f /usr/local/var/log/preheat.log
sudo rm -f /run/preheat.pid

# Reload systemd
sudo systemctl daemon-reload

echo "✓ Old installation removed"
echo ""
echo "📦 Installing preheat..."

# Build and install
make clean || true
autoreconf --install --force
./configure
make -j$(nproc)
sudo make install

echo "✓ Preheat installed"
echo ""
echo "📝 Creating whitelist..."

# Create whitelist directory
sudo mkdir -p /etc/preheat.d

# Create whitelist with your apps
sudo tee /etc/preheat.d/apps.list > /dev/null <<EOF
# Preheat Priority Apps Whitelist
# These apps will always be preloaded for faster startup

# Web Browser
/usr/bin/firefox

# Antigravity IDE
/usr/bin/antigravity
/usr/share/antigravity/antigravity

# Terminal
/usr/bin/gnome-terminal
/usr/bin/kgx
/usr/bin/konsole
/usr/bin/qterminal
EOF

echo "✓ Whitelist created: /etc/preheat.d/apps.list"
echo ""
echo "⚙️  Configuring..."

# Update config to use whitelist
sudo tee /usr/local/etc/preheat.conf > /dev/null <<EOF
[model]
cycle = 20
minsize = 2000000
memtotal = -10
memfree = 50
memcached = 0
usecorrelation = true

[system]
doscan = true
dopredict = true
autosave = 3600
maxprocs = 30
sortstrategy = 3
manualapps = /etc/preheat.d/apps.list

[ignore]
exeprefix = !/usr/sbin/;!/usr/local/sbin/;/usr/;!/
mapprefix = /usr/;/lib;/var/cache/;!/
EOF

echo "✓ Configuration updated"
echo ""
echo "🚀 Starting service..."

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable preheat.service
sudo systemctl start preheat.service

# Wait and check
sleep 2
if sudo systemctl is-active --quiet preheat.service; then
    echo "✅ Preheat is running!"
else
    echo "⚠️  Service failed to start - check: sudo journalctl -u preheat -n 50"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✨ Clean reinstall complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Whitelisted apps (always preloaded):"
echo "   • Firefox"
echo "   • Antigravity IDE"  
echo "   • Terminal (gnome-terminal/kgx/konsole)"
echo ""
echo "📊 Check status:"
echo "   sudo systemctl status preheat"
echo ""
echo "📜 View logs:"
echo "   sudo tail -f /usr/local/var/log/preheat.log"
echo ""
echo "💡 Apps will start faster after preheat learns your patterns (~1-2 hours)"
echo ""
