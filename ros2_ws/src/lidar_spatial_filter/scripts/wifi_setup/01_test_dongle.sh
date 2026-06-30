#!/bin/bash
# =============================================================
# Script 1: Test WiFi Dongle Compatibility
# Untuk KRIA KR260 + TP-Link TL-WN725N (RTL8188EUS)
# 
# Usage: ./01_test_dongle.sh
# Jalankan SETELAH colok dongle ke USB port
# =============================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo "=============================================="
echo "    WiFi Dongle Compatibility Test"
echo "    KRIA KR260 + TL-WN725N"
echo "=============================================="
echo ""

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

print_pass() {
    echo -e "${GREEN}[✓ PASS]${NC} $1"
    ((PASS_COUNT++))
}

print_fail() {
    echo -e "${RED}[✗ FAIL]${NC} $1"
    ((FAIL_COUNT++))
}

print_warn() {
    echo -e "${YELLOW}[⚠ WARN]${NC} $1"
    ((WARN_COUNT++))
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# =========================================
# TEST 1: USB Detection
# =========================================
echo "─────────────────────────────────────────────"
echo "TEST 1: USB Device Detection"
echo "─────────────────────────────────────────────"

USB_INFO=$(lsusb 2>/dev/null)

# Check for RTL8188EUS (TL-WN725N v1/v2)
if echo "$USB_INFO" | grep -qi "0bda:8179\|RTL8188EUS\|RTL8188EU"; then
    print_pass "TL-WN725N (RTL8188EUS) terdeteksi!"
    CHIPSET="RTL8188EUS"
    USB_ID="0bda:8179"
# Check for RTL8188CUS (alternative nano dongle)
elif echo "$USB_INFO" | grep -qi "0bda:8176\|RTL8188CUS"; then
    print_pass "RTL8188CUS terdeteksi (compatible)"
    CHIPSET="RTL8188CUS"
    USB_ID="0bda:8176"
# Check for Atheros AR9271 (TL-WN722N v1)
elif echo "$USB_INFO" | grep -qi "0cf3:9271\|AR9271"; then
    print_pass "AR9271 terdeteksi (TL-WN722N v1)"
    CHIPSET="AR9271"
    USB_ID="0cf3:9271"
else
    print_fail "WiFi dongle tidak terdeteksi!"
    echo ""
    echo "USB devices yang ada:"
    echo "$USB_INFO"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Pastikan dongle sudah dicolok dengan benar"
    echo "  2. Coba port USB lain"
    echo "  3. Coba cabut-colok ulang"
    exit 1
fi

echo ""
echo "  Chipset: $CHIPSET"
echo "  USB ID:  $USB_ID"
echo ""

# =========================================
# TEST 2: Kernel Driver
# =========================================
echo "─────────────────────────────────────────────"
echo "TEST 2: Kernel Driver"
echo "─────────────────────────────────────────────"

DRIVER_LOADED=""

if lsmod | grep -q "r8188eu\|rtl8188eu\|8188eu"; then
    print_pass "Driver rtl8188eu loaded"
    DRIVER_LOADED="rtl8188eu"
elif lsmod | grep -q "rtl8192cu\|8192cu"; then
    print_pass "Driver rtl8192cu loaded"
    DRIVER_LOADED="rtl8192cu"
elif lsmod | grep -q "ath9k_htc"; then
    print_pass "Driver ath9k_htc loaded"
    DRIVER_LOADED="ath9k_htc"
else
    print_warn "Driver tidak terdeteksi di lsmod"
    echo "         Mungkin menggunakan built-in kernel driver"
    DRIVER_LOADED="built-in"
fi

echo ""

# =========================================
# TEST 3: Network Interface
# =========================================
echo "─────────────────────────────────────────────"
echo "TEST 3: Wireless Network Interface"
echo "─────────────────────────────────────────────"

# Find wireless interface
WLAN_IFACE=""

# Check standard naming
if ip link show wlan0 &>/dev/null; then
    WLAN_IFACE="wlan0"
fi

# Check predictable naming (wlx...)
if [ -z "$WLAN_IFACE" ]; then
    WLAN_IFACE=$(ip link show | grep -oP 'wlx[a-f0-9]+' | head -1)
fi

# Check any wireless interface
if [ -z "$WLAN_IFACE" ]; then
    WLAN_IFACE=$(iw dev 2>/dev/null | grep Interface | awk '{print $2}' | head -1)
fi

if [ -n "$WLAN_IFACE" ]; then
    print_pass "Wireless interface ditemukan: $WLAN_IFACE"
    
    # Get MAC address
    MAC=$(ip link show "$WLAN_IFACE" | grep link/ether | awk '{print $2}')
    echo "         MAC Address: $MAC"
    
    # Check interface state
    STATE=$(ip link show "$WLAN_IFACE" | grep -oP 'state \K\w+')
    echo "         State: $STATE"
else
    print_fail "Tidak ada wireless interface!"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Cek dmesg untuk error:"
    echo "     dmesg | tail -30"
    echo "  2. Coba load driver manual:"
    echo "     sudo modprobe rtl8188eu"
    exit 1
fi

echo ""

# =========================================
# TEST 4: WiFi Scanning
# =========================================
echo "─────────────────────────────────────────────"
echo "TEST 4: WiFi Network Scanning"
echo "─────────────────────────────────────────────"

# Bring interface up
sudo ip link set "$WLAN_IFACE" up 2>/dev/null || true

# Scan networks
SCAN_RESULT=$(sudo iwlist "$WLAN_IFACE" scan 2>/dev/null | grep -c "ESSID" || echo "0")

if [ "$SCAN_RESULT" -gt 0 ]; then
    print_pass "Dapat scan WiFi networks: $SCAN_RESULT networks ditemukan"
    
    # Show first 5 networks
    echo ""
    echo "  Networks terdeteksi:"
    sudo iwlist "$WLAN_IFACE" scan 2>/dev/null | grep "ESSID" | head -5 | while read line; do
        echo "    $line"
    done
else
    print_warn "Tidak ada WiFi network terdeteksi"
    echo "         Mungkin tidak ada WiFi di sekitar atau antenna lemah"
fi

echo ""

# =========================================
# TEST 5: Kernel Messages
# =========================================
echo "─────────────────────────────────────────────"
echo "TEST 5: Kernel Log Check"
echo "─────────────────────────────────────────────"

# Check for errors in dmesg
ERRORS=$(dmesg | tail -50 | grep -i "error\|fail" | grep -i "usb\|wlan\|wireless\|rtl\|ath" | head -3)

if [ -z "$ERRORS" ]; then
    print_pass "Tidak ada error di kernel log"
else
    print_warn "Ada pesan error di kernel log:"
    echo "$ERRORS" | while read line; do
        echo "    $line"
    done
fi

echo ""

# =========================================
# SUMMARY
# =========================================
echo "=============================================="
echo "                 SUMMARY"
echo "=============================================="
echo ""
echo -e "  ${GREEN}Passed:${NC}  $PASS_COUNT"
echo -e "  ${RED}Failed:${NC}  $FAIL_COUNT"
echo -e "  ${YELLOW}Warning:${NC} $WARN_COUNT"
echo ""

if [ "$FAIL_COUNT" -eq 0 ]; then
    echo -e "${GREEN}╔═══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  DONGLE COMPATIBLE! Ready for setup.      ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════╝${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Run: ./02_setup_wifi.sh"
    echo "  2. Enter your WiFi credentials"
    echo ""
    
    # Save interface name for next script
    echo "$WLAN_IFACE" > /tmp/kria_wlan_iface
    echo "Interface name saved to /tmp/kria_wlan_iface"
else
    echo -e "${RED}╔═══════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  DONGLE NOT COMPATIBLE or NOT WORKING     ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════╝${NC}"
    echo ""
    echo "Troubleshooting steps:"
    echo "  1. Try different USB port"
    echo "  2. Check: dmesg | tail -50"
    echo "  3. Try: sudo modprobe rtl8188eu"
    echo "  4. Check kernel: uname -r"
    exit 1
fi
