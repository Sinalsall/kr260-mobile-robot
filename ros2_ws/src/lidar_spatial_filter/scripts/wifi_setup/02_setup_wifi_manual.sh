#!/bin/bash
# =============================================================
# Manual WiFi Setup - KRIA KR260
# Untuk kasus script otomatis tidak jalan
# =============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}=============================================="
echo "    Manual WiFi Setup"
echo "    KRIA KR260"
echo "==============================================${NC}"
echo ""

# Detect interface
WLAN_IFACE=$(ip link show | grep -oP 'wlx[a-f0-9]+' | head -1)

if [ -z "$WLAN_IFACE" ]; then
    echo -e "${RED}Error: No wireless interface found!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Interface detected: $WLAN_IFACE${NC}"
echo ""

# Scan networks
echo "─────────────────────────────────────────────"
echo "Available WiFi Networks:"
echo "─────────────────────────────────────────────"
sudo iwlist "$WLAN_IFACE" scan 2>/dev/null | grep "ESSID" | grep -v '""' | sort -u | head -15
echo ""

# Get credentials
read -p "Enter WiFi SSID: " WIFI_SSID
read -sp "Enter WiFi Password: " WIFI_PASS
echo ""
echo ""

if [ -z "$WIFI_SSID" ]; then
    echo -e "${RED}Error: SSID cannot be empty${NC}"
    exit 1
fi

# Get current eth1 IP for reference
ETH1_IP=$(ip addr show eth1 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)
if [ -n "$ETH1_IP" ]; then
    NETWORK_PREFIX=$(echo "$ETH1_IP" | cut -d. -f1-3)
    echo "Detected network from eth1: ${NETWORK_PREFIX}.x"
else
    NETWORK_PREFIX="192.168.0"
fi

echo ""
echo "IP Configuration:"
echo "  1. Static IP: ${NETWORK_PREFIX}.100 (recommended for ROS2)"
echo "  2. DHCP (automatic)"
echo ""
read -p "Choice [1/2, default=1]: " IP_CHOICE

STATIC_IP="${NETWORK_PREFIX}.100"
GATEWAY="${NETWORK_PREFIX}.1"

if [ "$IP_CHOICE" = "2" ]; then
    USE_STATIC=false
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
fi

echo ""
echo "─────────────────────────────────────────────"
echo "Setting up connection..."
echo "─────────────────────────────────────────────"

CONNECTION_NAME="kria-robot-wifi"

# Delete existing
nmcli con delete "$CONNECTION_NAME" 2>/dev/null || true

# Create connection
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

echo "Activating connection..."
nmcli con up "$CONNECTION_NAME"

sleep 3

# Check result
WIFI_IP=$(ip addr show "$WLAN_IFACE" | grep "inet " | awk '{print $2}' | cut -d/ -f1)

echo ""
echo "─────────────────────────────────────────────"
echo "Connection Status"
echo "─────────────────────────────────────────────"

if [ -n "$WIFI_IP" ]; then
    echo -e "${GREEN}✓ Connected successfully!${NC}"
    echo ""
    echo "  Interface: $WLAN_IFACE"
    echo "  SSID:      $WIFI_SSID"
    echo "  IP:        $WIFI_IP"
    echo ""
    
    # Test connectivity
    if ping -c 2 -W 2 8.8.8.8 &>/dev/null; then
        echo -e "  ${GREEN}✓ Internet: OK${NC}"
    else
        echo -e "  ${YELLOW}⚠ Internet: Not reachable${NC}"
    fi
    
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
    
    # Save for next script
    echo "$WIFI_IP" > /tmp/kria_wifi_ip
    echo "$WLAN_IFACE" > /tmp/kria_wlan_iface
    
    echo "Next step: ./03_setup_cyclonedds.sh"
    
else
    echo -e "${RED}✗ Connection failed!${NC}"
    echo ""
    echo "Check: nmcli con show $CONNECTION_NAME"
    exit 1
fi

echo ""
