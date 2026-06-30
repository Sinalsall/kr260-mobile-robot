#!/bin/bash
# =============================================================
# Complete WiFi + Tailscale Setup
# 1. Set WiFi static IP
# 2. Configure Tailscale to prefer WiFi
# 3. Setup CycloneDDS for WiFi
# =============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}=============================================="
echo "    WiFi Static IP + Tailscale Setup"
echo "    KRIA KR260"
echo "==============================================${NC}"
echo ""

WLAN_IFACE="wlx6c4cbc88d820"
STATIC_IP="192.168.0.100"
GATEWAY="192.168.0.1"

# =========================================
# Step 1: Set Static IP for WiFi
# =========================================

echo -e "${BLUE}[1/4] Setting WiFi to Static IP...${NC}"

# Get current connection name
WIFI_CON=$(nmcli -t -f NAME,DEVICE con show --active | grep "$WLAN_IFACE" | cut -d: -f1)

if [ -z "$WIFI_CON" ]; then
    echo -e "${RED}Error: WiFi not connected!${NC}"
    exit 1
fi

echo "  WiFi Connection: $WIFI_CON"
echo "  Setting static IP: $STATIC_IP"

# Set to static IP
sudo nmcli con modify "$WIFI_CON" \
    ipv4.method manual \
    ipv4.addresses "${STATIC_IP}/24" \
    ipv4.gateway "$GATEWAY" \
    ipv4.dns "8.8.8.8,8.8.4.4" \
    connection.autoconnect yes \
    connection.autoconnect-priority 10

# Reconnect to apply
sudo nmcli con down "$WIFI_CON"
sleep 2
sudo nmcli con up "$WIFI_CON"
sleep 3

# Verify
WIFI_IP=$(ip addr show "$WLAN_IFACE" | grep "inet " | awk '{print $2}' | cut -d/ -f1)

if [ "$WIFI_IP" = "$STATIC_IP" ]; then
    echo -e "  ${GREEN}✓ WiFi Static IP: $WIFI_IP${NC}"
else
    echo -e "  ${YELLOW}⚠ WiFi IP: $WIFI_IP (expected $STATIC_IP)${NC}"
fi

echo ""

# =========================================
# Step 2: Configure Tailscale for WiFi
# =========================================

echo -e "${BLUE}[2/4] Configuring Tailscale to prefer WiFi...${NC}"

# Check if Tailscale is running
if systemctl is-active --quiet tailscaled; then
    echo "  Tailscale is running"
    
    # Set to use WiFi interface (via routing preference)
    # Tailscale auto-detects, but we can influence it
    
    # Option A: Set interface preference in routing
    # This ensures Tailscale prefers WiFi for outbound connections
    sudo ip route add default via $GATEWAY dev $WLAN_IFACE metric 50 2>/dev/null || true
    
    # Option B: Restart Tailscale to re-detect interfaces
    echo "  Restarting Tailscale to re-detect interfaces..."
    sudo systemctl restart tailscaled
    sleep 3
    
    # Check Tailscale status
    TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "N/A")
    echo -e "  ${GREEN}✓ Tailscale IP: $TAILSCALE_IP${NC}"
    
else
    echo -e "  ${YELLOW}⚠ Tailscale not running${NC}"
fi

echo ""

# =========================================
# Step 3: Set Interface Priority (eth1 backup)
# =========================================

echo -e "${BLUE}[3/4] Setting interface priorities...${NC}"

# WiFi = primary (priority 10)
# eth1 = backup (priority 5)

# Get eth1 connection
ETH_CON=$(nmcli -t -f NAME,DEVICE con show --active | grep "eth1" | cut -d: -f1)

if [ -n "$ETH_CON" ]; then
    echo "  Setting eth1 as backup (lower priority)..."
    sudo nmcli con modify "$ETH_CON" \
        connection.autoconnect-priority 5
    
    echo -e "  ${GREEN}✓ WiFi priority: 10 (primary)${NC}"
    echo -e "  ${GREEN}✓ eth1 priority: 5 (backup)${NC}"
else
    echo "  eth1 connection not found (OK if using WiFi only)"
fi

echo ""

# =========================================
# Step 4: Verify & Summary
# =========================================

echo -e "${BLUE}[4/4] Network Summary...${NC}"
echo ""

echo "─────────────────────────────────────────────"
echo "Network Interfaces:"
echo "─────────────────────────────────────────────"
ip -4 addr show | grep -E "inet " | grep -v "127.0.0.1"
echo ""

echo "─────────────────────────────────────────────"
echo "Default Routes:"
echo "─────────────────────────────────────────────"
ip route show | grep default
echo ""

echo "─────────────────────────────────────────────"
echo "Active Connections:"
echo "─────────────────────────────────────────────"
nmcli con show --active
echo ""

echo -e "${GREEN}╔═══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Network Setup Complete!                  ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════╝${NC}"
echo ""

echo "Configuration:"
echo "  • WiFi (wlx6c4cbc88d820): $STATIC_IP (static, primary)"
echo "  • eth1: backup interface"
echo "  • Tailscale: accessible via WiFi"
echo ""
echo "Remote Access:"
echo "  • Tailscale IP: $TAILSCALE_IP (stable, use this for remote)"
echo "  • WiFi Direct: $STATIC_IP (when on same network)"
echo ""
echo "Next: Setup CycloneDDS for ROS2"
echo "  cd ~/kria_ros2_ws/src/lidar_spatial_filter/scripts/wifi_setup"
echo "  ./03_setup_cyclonedds.sh"
echo ""
