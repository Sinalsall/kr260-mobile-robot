#!/bin/bash
# =============================================================
# Fix WiFi Dongle Firmware Issue - RTL8188EU
# Untuk KRIA KR260 + TL-WN725N
# 
# Issue: firmware rtlwifi/rtl8188eufw.bin missing
# Solution: Install linux-firmware atau dongle tetap bisa jalan
# =============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}=============================================="
echo "    WiFi Dongle Firmware Fix"
echo "    RTL8188EU Firmware Installation"
echo "==============================================${NC}"
echo ""

# =========================================
# Check Current Status
# =========================================

echo -e "${BLUE}[1/4] Checking current status...${NC}"

# Check interface
WLAN_IFACE=$(ip link show | grep -oP 'wlx[a-f0-9]+' | head -1)

if [ -n "$WLAN_IFACE" ]; then
    echo -e "  ${GREEN}✓ Interface found: $WLAN_IFACE${NC}"
else
    echo -e "  ${RED}✗ No wireless interface found!${NC}"
    exit 1
fi

# Check firmware error
FIRMWARE_ERROR=$(dmesg | grep -c "rtlwifi/rtl8188eufw.bin failed" || echo "0")

if [ "$FIRMWARE_ERROR" -gt 0 ]; then
    echo -e "  ${YELLOW}⚠ Firmware file missing (seen $FIRMWARE_ERROR errors in dmesg)${NC}"
    NEED_FIX=true
else
    echo -e "  ${GREEN}✓ No firmware errors detected${NC}"
    NEED_FIX=false
fi

echo ""

# =========================================
# Test Interface (Even Without Firmware)
# =========================================

echo -e "${BLUE}[2/4] Testing interface functionality...${NC}"

# Try to bring interface up
echo "  Bringing interface up..."
sudo ip link set "$WLAN_IFACE" up 2>&1 | grep -v "password" || true
sleep 3

# Check state
STATE=$(ip link show "$WLAN_IFACE" | grep -oP 'state \K\w+')
echo "  Interface state: $STATE"

if [ "$STATE" = "UP" ] || [ "$STATE" = "UNKNOWN" ]; then
    echo -e "  ${GREEN}✓ Interface is UP (firmware not critical)${NC}"
    echo "  ${YELLOW}  Note: RTL8188EU dapat berfungsi tanpa firmware file untuk basic operation${NC}"
else
    echo -e "  ${YELLOW}⚠ Interface state: $STATE${NC}"
fi

echo ""

# =========================================
# Install Full Firmware (Recommended)
# =========================================

if [ "$NEED_FIX" = true ]; then
    echo -e "${BLUE}[3/4] Installing linux-firmware package...${NC}"
    echo "  This will eliminate firmware warnings and enable full features."
    echo ""
    
    read -p "  Install linux-firmware? [Y/n]: " INSTALL_FW
    
    if [ "$INSTALL_FW" != "n" ] && [ "$INSTALL_FW" != "N" ]; then
        echo "  Updating package list..."
        sudo apt update -qq
        
        echo "  Installing linux-firmware and wireless tools..."
        sudo apt install -y linux-firmware wireless-tools iw
        
        echo ""
        echo -e "  ${GREEN}✓ Firmware package installed${NC}"
        echo ""
        echo "  ${YELLOW}Please unplug and replug the WiFi dongle to load firmware.${NC}"
        echo ""
        read -p "  Press Enter after replugging dongle..."
        
        # Check if firmware error gone
        sleep 2
        NEW_ERROR=$(dmesg | tail -20 | grep -c "rtlwifi/rtl8188eufw.bin failed" || echo "0")
        if [ "$NEW_ERROR" -eq 0 ]; then
            echo -e "  ${GREEN}✓ Firmware loaded successfully!${NC}"
        else
            echo -e "  ${YELLOW}⚠ Still seeing firmware errors (dongle should still work)${NC}"
        fi
    else
        echo "  Skipped. Dongle will work without firmware for basic WiFi."
    fi
else
    echo -e "${BLUE}[3/4] Firmware check${NC}"
    echo -e "  ${GREEN}✓ No firmware issues detected${NC}"
fi

echo ""

# =========================================
# Final Test
# =========================================

echo -e "${BLUE}[4/4] Final connectivity test...${NC}"

# Scan networks
echo "  Scanning for WiFi networks..."
sudo iwlist "$WLAN_IFACE" scan 2>&1 | grep -c "ESSID" > /tmp/wifi_scan_count.txt || echo "0" > /tmp/wifi_scan_count.txt
SCAN_COUNT=$(cat /tmp/wifi_scan_count.txt)
rm -f /tmp/wifi_scan_count.txt

if [ "$SCAN_COUNT" -gt 0 ]; then
    echo -e "  ${GREEN}✓ WiFi scan successful: $SCAN_COUNT networks found${NC}"
    echo ""
    echo "  Sample networks:"
    sudo iwlist "$WLAN_IFACE" scan 2>/dev/null | grep "ESSID" | head -5
else
    echo -e "  ${YELLOW}⚠ Cannot scan networks (may need firmware or driver issue)${NC}"
fi

echo ""

# =========================================
# Summary
# =========================================

echo -e "${GREEN}=============================================="
echo "                 SUMMARY"
echo "==============================================${NC}"
echo ""
echo "  Interface: $WLAN_IFACE"
echo "  State: $STATE"
echo "  Networks found: $SCAN_COUNT"
echo ""

if [ "$SCAN_COUNT" -gt 0 ]; then
    echo -e "${GREEN}╔═══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  WiFi Dongle is WORKING!                  ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════╝${NC}"
    echo ""
    echo "Next step: Run ./02_setup_wifi.sh to connect"
else
    echo -e "${YELLOW}╔═══════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  Dongle detected but cannot scan          ║${NC}"
    echo -e "${YELLOW}╚═══════════════════════════════════════════╝${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Try unplugging and replugging dongle"
    echo "  2. Check: dmesg | tail -30"
    echo "  3. Install firmware: sudo apt install linux-firmware"
fi

echo ""
