#!/bin/bash
# =============================================================
# Script 2: Setup WiFi Connection
# Untuk KRIA KR260 + TP-Link TL-WN725N
# 
# Usage: ./02_setup_wifi.sh [SSID] [PASSWORD]
#    or: ./02_setup_wifi.sh (interactive mode)
# =============================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo "=============================================="
echo "    WiFi Connection Setup"
echo "    KRIA KR260"
echo "=============================================="
echo ""

# Get interface name from previous script or detect
if [ -f /tmp/kria_wlan_iface ]; then
    WLAN_IFACE=$(cat /tmp/kria_wlan_iface)
else
    WLAN_IFACE=$(iw dev 2>/dev/null | grep Interface | awk '{print $2}' | head -1)
fi

if [ -z "$WLAN_IFACE" ]; then
    echo -e "${RED}Error: No wireless interface found!${NC}"
    echo "Please run ./01_test_dongle.sh first"
    exit 1
fi

echo -e "${BLUE}Using interface: $WLAN_IFACE${NC}"
echo ""

# =========================================
# Get WiFi Credentials
# =========================================

if [ -n "$1" ] && [ -n "$2" ]; then
    WIFI_SSID="$1"
    WIFI_PASS="$2"
else
    echo "─────────────────────────────────────────────"
    echo "Available WiFi Networks:"
    echo "─────────────────────────────────────────────"
    
    # Scan and display networks
    sudo ip link set "$WLAN_IFACE" up 2>/dev/null || true
    sleep 2
    
    nmcli dev wifi list 2>/dev/null || sudo iwlist "$WLAN_IFACE" scan | grep "ESSID" | head -10
    
    echo ""
    echo "─────────────────────────────────────────────"
    read -p "Enter WiFi SSID: " WIFI_SSID
    read -sp "Enter WiFi Password: " WIFI_PASS
    echo ""
fi

if [ -z "$WIFI_SSID" ]; then
    echo -e "${RED}Error: SSID cannot be empty${NC}"
    exit 1
fi

# =========================================
# Configure Static IP (for ROS2 consistency)
# =========================================

echo ""
echo "─────────────────────────────────────────────"
echo "IP Configuration"
echo "─────────────────────────────────────────────"

# Check current eth1 IP to determine network
CURRENT_ETH1_IP=$(ip addr show eth1 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)
if [ -n "$CURRENT_ETH1_IP" ]; then
    NETWORK_PREFIX=$(echo "$CURRENT_ETH1_IP" | cut -d. -f1-3)
    echo "Detected network from eth1: ${NETWORK_PREFIX}.x"
else
    NETWORK_PREFIX="192.168.0"
    echo "Using default network: ${NETWORK_PREFIX}.x"
fi

echo ""
echo "Choose IP configuration:"
echo "  1. Static IP: ${NETWORK_PREFIX}.100 (recommended for ROS2)"
echo "  2. DHCP (automatic IP)"
echo ""
read -p "Choice [1/2, default=1]: " IP_CHOICE

STATIC_IP="${NETWORK_PREFIX}.100"
GATEWAY="${NETWORK_PREFIX}.1"

if [ "$IP_CHOICE" = "2" ]; then
    USE_STATIC=false
    echo "Using DHCP"
else
    USE_STATIC=true
    read -p "Static IP [default: $STATIC_IP]: " CUSTOM_IP
    if [ -n "$CUSTOM_IP" ]; then
        STATIC_IP="$CUSTOM_IP"
    fi
    read -p "Gateway [default: $GATEWAY]: " CUSTOM_GW
    if [ -n "$CUSTOM_GW" ]; then
        GATEWAY="$CUSTOM_GW"
    fi
    echo "Using Static IP: $STATIC_IP"
fi

# =========================================
# Setup Connection
# =========================================

echo ""
echo "─────────────────────────────────────────────"
echo "Setting up WiFi connection..."
echo "─────────────────────────────────────────────"

CONNECTION_NAME="kria-robot-wifi"

# Delete existing connection if exists
nmcli con delete "$CONNECTION_NAME" 2>/dev/null || true

# Create new connection
echo "Creating connection profile..."

if [ "$USE_STATIC" = true ]; then
    nmcli con add type wifi \
        con-name "$CONNECTION_NAME" \
        ifname "$WLAN_IFACE" \
        ssid "$WIFI_SSID" \
        wifi-sec.key-mgmt wpa-psk \
        wifi-sec.psk "$WIFI_PASS" \
        ipv4.method manual \
        ipv4.addresses "${STATIC_IP}/24" \
        ipv4.gateway "$GATEWAY" \
        ipv4.dns "8.8.8.8,8.8.4.4" \
        connection.autoconnect yes
else
    nmcli con add type wifi \
        con-name "$CONNECTION_NAME" \
        ifname "$WLAN_IFACE" \
        ssid "$WIFI_SSID" \
        wifi-sec.key-mgmt wpa-psk \
        wifi-sec.psk "$WIFI_PASS" \
        ipv4.method auto \
        connection.autoconnect yes
fi

echo ""
echo "Activating connection..."
nmcli con up "$CONNECTION_NAME"

# Wait for connection
sleep 3

# =========================================
# Verify Connection
# =========================================

echo ""
echo "─────────────────────────────────────────────"
echo "Connection Status"
echo "─────────────────────────────────────────────"

# Get assigned IP
WIFI_IP=$(ip addr show "$WLAN_IFACE" | grep "inet " | awk '{print $2}' | cut -d/ -f1)

if [ -n "$WIFI_IP" ]; then
    echo -e "${GREEN}✓ Connected successfully!${NC}"
    echo ""
    echo "  Interface: $WLAN_IFACE"
    echo "  SSID:      $WIFI_SSID"
    echo "  IP:        $WIFI_IP"
    
    # Test connectivity
    echo ""
    echo "Testing connectivity..."
    
    if ping -c 2 -W 2 8.8.8.8 &>/dev/null; then
        echo -e "  ${GREEN}✓ Internet: OK${NC}"
    else
        echo -e "  ${YELLOW}⚠ Internet: Not reachable (mungkin diblokir WARP?)${NC}"
    fi
    
    # Test gateway
    if ping -c 2 -W 2 "$GATEWAY" &>/dev/null; then
        echo -e "  ${GREEN}✓ Gateway: OK${NC}"
    else
        echo -e "  ${YELLOW}⚠ Gateway: Not reachable${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  WiFi Setup Complete!                     ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════╝${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Run: ./03_setup_cyclonedds.sh"
    echo "  2. Update CycloneDDS config for wireless"
    echo ""
    
    # Save WiFi IP for next script
    echo "$WIFI_IP" > /tmp/kria_wifi_ip
    echo "$WLAN_IFACE" > /tmp/kria_wlan_iface
    
else
    echo -e "${RED}✗ Connection failed!${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Check password is correct"
    echo "  2. Check WiFi is in range"
    echo "  3. Run: nmcli con show $CONNECTION_NAME"
    echo "  4. Run: journalctl -u NetworkManager --since '5 minutes ago'"
    exit 1
fi
