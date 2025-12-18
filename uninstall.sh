#!/bin/bash
#
# Preheat Uninstaller
# Safely removes preheat with optional data preservation
#
# Phase 2: Uninstall-Time Data Preservation

set -e

# Colors and formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Data locations
STATE_DIR="/usr/local/var/lib/preheat"
CONFIG_DIR="/etc/preheat.d"
LOG_FILE="/usr/local/var/log/preheat.log"
MAIN_CONFIG="/usr/local/etc/preheat.conf"

# Parse flags
PURGE_DATA=false
KEEP_DATA=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --purge-data)
            PURGE_DATA=true
            shift
            ;;
        --keep-data)
            KEEP_DATA=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --keep-data    Preserve all configuration and state data"
            echo "  --purge-data   Remove all configuration and state data"
            echo "  --help, -h     Show this help message"
            echo ""
            echo "If no option is specified, you will be prompted (interactive mode)"
            echo "or data will be kept by default (non-interactive mode)."
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}${BOLD}✗ Error:${NC} This script must be run as root"
    echo -e "${DIM}  Try: ${CYAN}sudo $0${NC}"
    exit 1
fi

# Header
echo ""
echo -e "${CYAN}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║                                                                ║${NC}"
echo -e "${CYAN}${BOLD}║                    PREHEAT UNINSTALLER                         ║${NC}"
echo -e "${CYAN}${BOLD}║                                                                ║${NC}"
echo -e "${CYAN}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Step 1: Stop and disable service
echo -e "${CYAN}[1/3]${NC} Stopping service..."
if systemctl is-active --quiet preheat.service 2>/dev/null; then
    systemctl stop preheat.service
    echo -e "${GREEN}      ✓ Service stopped${NC}"
else
    echo -e "${DIM}      Service not running${NC}"
fi

if systemctl is-enabled --quiet preheat.service 2>/dev/null; then
    systemctl disable preheat.service > /dev/null 2>&1
    echo -e "${GREEN}      ✓ Service disabled${NC}"
else
    echo -e "${DIM}      Service not enabled${NC}"
fi

# Step 2: Remove binaries and service
echo -e "${CYAN}[2/3]${NC} Removing binaries..."

# Try to use make uninstall if available
if [ -f Makefile ]; then
    make uninstall > /dev/null 2>&1 || {
        echo -e "${YELLOW}      ⚠ make uninstall failed, removing manually${NC}"
        rm -f /usr/local/sbin/preheat
        rm -f /usr/local/sbin/preheat-ctl
        rm -f /usr/local/lib/systemd/system/preheat.service
        rm -f /usr/local/etc/logrotate.d/preheat.logrotate
    }
    echo -e "${GREEN}      ✓ Binaries removed${NC}"
else
    echo -e "${YELLOW}      ⚠ Makefile not found, removing manually${NC}"
    rm -f /usr/local/sbin/preheat
    rm -f /usr/local/sbin/preheat-ctl
    rm -f /usr/local/lib/systemd/system/preheat.service
    rm -f /usr/local/etc/logrotate.d/preheat.logrotate
    echo -e "${GREEN}      ✓ Binaries removed${NC}"
fi

systemctl daemon-reload 2>/dev/null

# Step 3: Handle data preservation
echo -e "${CYAN}[3/3]${NC} Managing data..."

# Determine if we should remove data
REMOVE_DATA=false

if [ "$PURGE_DATA" = true ]; then
    REMOVE_DATA=true
    echo -e "${DIM}      --purge-data flag set${NC}"
elif [ "$KEEP_DATA" = true ]; then
    REMOVE_DATA=false
    echo -e "${DIM}      --keep-data flag set${NC}"
elif [ -t 0 ]; then
    # Interactive prompt
    echo ""
    echo -e "${YELLOW}Keep preheat's data and history for future use?${NC}"
    echo -e "${DIM}  This includes:${NC}"
    echo -e "${DIM}    - Application tracking data ($STATE_DIR)${NC}"
    echo -e "${DIM}    - Manual whitelist ($CONFIG_DIR)${NC}"
    echo -e "${DIM}    - Configuration ($MAIN_CONFIG)${NC}"
    read -p "$(echo -e ${BOLD}Keep data? [Y/n]:${NC} )" choice
    choice=${choice:-Y}
    
    if [[ ! "$choice" =~ ^[Yy]$ ]]; then
        REMOVE_DATA=true
        echo ""
        echo -e "${YELLOW}⚠ This will permanently delete all preheat data!${NC}"
        read -p "$(echo -e ${BOLD}Are you sure? [y/N]:${NC} )" confirm
        confirm=${confirm:-N}
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            REMOVE_DATA=false
            echo -e "${GREEN}      Data preservation restored${NC}"
        fi
    fi
else
    # Non-interactive: keep data by default (safer)
    REMOVE_DATA=false
    echo -e "${DIM}      Non-interactive mode: preserving data${NC}"
fi

if [ "$REMOVE_DATA" = true ]; then
    echo ""
    echo -e "${YELLOW}Removing all data...${NC}"
    
    [ -d "$STATE_DIR" ] && rm -rf "$STATE_DIR" && echo -e "${DIM}      Removed: $STATE_DIR${NC}"
    [ -d "$CONFIG_DIR" ] && rm -rf "$CONFIG_DIR" && echo -e "${DIM}      Removed: $CONFIG_DIR${NC}"
    [ -f "$LOG_FILE" ] && rm -f "$LOG_FILE" && echo -e "${DIM}      Removed: $LOG_FILE${NC}"
    [ -f "$MAIN_CONFIG" ] && rm -f "$MAIN_CONFIG" && echo -e "${DIM}      Removed: $MAIN_CONFIG${NC}"
    
    echo -e "${GREEN}      ✓ All data removed${NC}"
else
    echo ""
    echo -e "${GREEN}Data preserved in:${NC}"
    [ -d "$STATE_DIR" ] && echo -e "${DIM}      ✓ $STATE_DIR${NC}"
    [ -d "$CONFIG_DIR" ] && echo -e "${DIM}      ✓ $CONFIG_DIR${NC}"
    [ -f "$MAIN_CONFIG" ] && echo -e "${DIM}      ✓ $MAIN_CONFIG${NC}"
    [ -f "$LOG_FILE" ] && echo -e "${DIM}      ✓ $LOG_FILE${NC}"
fi

# Success banner
echo ""
echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║                                                                ║${NC}"
echo -e "${GREEN}${BOLD}║                 ✓ UNINSTALLATION COMPLETE                      ║${NC}"
echo -e "${GREEN}${BOLD}║                                                                ║${NC}"
echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [ "$REMOVE_DATA" = false ]; then
    echo -e "${DIM}💡 Tip: Your data is preserved for future reinstalls${NC}"
    echo -e "${DIM}   To remove data later: sudo rm -rf $STATE_DIR $CONFIG_DIR${NC}"
else
    echo -e "${DIM}💡 All preheat data has been removed from your system${NC}"
fi

echo ""
