#!/bin/bash
# =============================================================
# Script 3: Update CycloneDDS for Wireless Operation
# Untuk KRIA KR260 + TP-Link TL-WN725N + ROS2
# 
# Usage: ./03_setup_cyclonedds.sh [LAPTOP_IP]
# =============================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$(dirname "$SCRIPT_DIR")/config"
WORKSPACE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo ""
echo "=============================================="
echo "    CycloneDDS Wireless Configuration"
echo "    KRIA KR260 + ROS2"
echo "=============================================="
echo ""

# =========================================
# Detect Interfaces and IPs
# =========================================

echo "─────────────────────────────────────────────"
echo "Network Detection"
echo "─────────────────────────────────────────────"

# Get wireless interface
if [ -f /tmp/kria_wlan_iface ]; then
    WLAN_IFACE=$(cat /tmp/kria_wlan_iface)
else
    WLAN_IFACE=$(iw dev 2>/dev/null | grep Interface | awk '{print $2}' | head -1)
fi

# Get WiFi IP
if [ -f /tmp/kria_wifi_ip ]; then
    WIFI_IP=$(cat /tmp/kria_wifi_ip)
else
    WIFI_IP=$(ip addr show "$WLAN_IFACE" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)
fi

# Get ethernet IP (backup)
ETH_IP=$(ip addr show eth1 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)

echo "  Wireless Interface: $WLAN_IFACE"
echo "  WiFi IP:            $WIFI_IP"
echo "  Ethernet IP (eth1): $ETH_IP"
echo ""

if [ -z "$WLAN_IFACE" ] || [ -z "$WIFI_IP" ]; then
    echo -e "${RED}Error: WiFi not configured!${NC}"
    echo "Please run ./02_setup_wifi.sh first"
    exit 1
fi

# =========================================
# Get Laptop IP
# =========================================

echo "─────────────────────────────────────────────"
echo "Laptop/Ground Station Configuration"
echo "─────────────────────────────────────────────"

# Check existing config for laptop IP
CURRENT_LAPTOP_IP=""
if [ -f "$CONFIG_DIR/cyclonedds.xml" ]; then
    CURRENT_LAPTOP_IP=$(grep -oP 'Peer address="\K[0-9.]+' "$CONFIG_DIR/cyclonedds.xml" | grep -v "localhost" | head -1)
fi

if [ -n "$1" ]; then
    LAPTOP_IP="$1"
elif [ -n "$CURRENT_LAPTOP_IP" ]; then
    echo "Current laptop IP in config: $CURRENT_LAPTOP_IP"
    read -p "Laptop IP [default: $CURRENT_LAPTOP_IP]: " LAPTOP_IP
    LAPTOP_IP="${LAPTOP_IP:-$CURRENT_LAPTOP_IP}"
else
    NETWORK_PREFIX=$(echo "$WIFI_IP" | cut -d. -f1-3)
    read -p "Enter laptop IP (e.g., ${NETWORK_PREFIX}.104): " LAPTOP_IP
fi

echo ""
echo "Laptop IP: $LAPTOP_IP"

# Test laptop connectivity
echo ""
echo "Testing laptop connectivity..."
if ping -c 2 -W 2 "$LAPTOP_IP" &>/dev/null; then
    echo -e "${GREEN}✓ Laptop reachable${NC}"
else
    echo -e "${YELLOW}⚠ Laptop not reachable - make sure it's on same network${NC}"
fi

# =========================================
# Choose Mode
# =========================================

echo ""
echo "─────────────────────────────────────────────"
echo "Interface Mode Selection"
echo "─────────────────────────────────────────────"
echo ""
echo "Choose CycloneDDS network mode:"
echo "  1. WiFi only ($WLAN_IFACE) - for wireless robot operation"
echo "  2. Ethernet only (eth1) - for wired development"
echo "  3. Both interfaces - for redundancy/testing"
echo ""
read -p "Choice [1/2/3, default=1]: " MODE_CHOICE

case "$MODE_CHOICE" in
    2)
        INTERFACE_CONFIG="eth1"
        BIND_IP="$ETH_IP"
        ;;
    3)
        INTERFACE_CONFIG="$WLAN_IFACE,eth1"
        BIND_IP="$WIFI_IP"
        ;;
    *)
        INTERFACE_CONFIG="$WLAN_IFACE"
        BIND_IP="$WIFI_IP"
        ;;
esac

echo ""
echo "Selected: $INTERFACE_CONFIG"

# =========================================
# Backup Existing Config
# =========================================

echo ""
echo "─────────────────────────────────────────────"
echo "Backup & Create New Config"
echo "─────────────────────────────────────────────"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)

if [ -f "$CONFIG_DIR/cyclonedds.xml" ]; then
    cp "$CONFIG_DIR/cyclonedds.xml" "$CONFIG_DIR/cyclonedds.xml.backup_$TIMESTAMP"
    echo "Backup created: cyclonedds.xml.backup_$TIMESTAMP"
fi

# =========================================
# Generate New CycloneDDS Config
# =========================================

cat > "$CONFIG_DIR/cyclonedds.xml" << EOF
<?xml version="1.0" encoding="UTF-8" ?>
<!--
  CycloneDDS Configuration for KRIA KR260 Robot
  Generated: $(date)
  
  Mode: Wireless ($WLAN_IFACE)
  KRIA IP: $WIFI_IP
  Laptop IP: $LAPTOP_IP
  
  This config bypasses CloudflareWARP/Tailscale by binding to physical interface only.
-->
<CycloneDDS xmlns="https://cdds.io/config"
            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xsi:schemaLocation="https://cdds.io/config https://raw.githubusercontent.com/eclipse-cyclonedds/cyclonedds/master/etc/cyclonedds.xsd">
  <Domain id="any">
    <General>
      <!-- Bind to WiFi interface, bypass VPN tunnels -->
      <Interfaces>
        <NetworkInterface name="$INTERFACE_CONFIG" priority="default" multicast="true" />
      </Interfaces>
      <AllowMulticast>spdp</AllowMulticast>
    </General>
    <Discovery>
      <!-- Unicast peer discovery for reliable connection -->
      <Peers>
        <Peer address="$LAPTOP_IP"/>
        <Peer address="localhost"/>
      </Peers>
      <ParticipantIndex>auto</ParticipantIndex>
      <MaxAutoParticipantIndex>120</MaxAutoParticipantIndex>
    </Discovery>
    <Internal>
      <SocketReceiveBufferSize min="default"/>
    </Internal>
    <Tracing>
      <!-- Uncomment for debugging -->
      <!-- <Verbosity>fine</Verbosity> -->
      <!-- <OutputFile>/tmp/cyclonedds.log</OutputFile> -->
    </Tracing>
  </Domain>
</CycloneDDS>
EOF

echo -e "${GREEN}✓ Created: $CONFIG_DIR/cyclonedds.xml${NC}"

# =========================================
# Generate Laptop Config
# =========================================

cat > "$CONFIG_DIR/cyclonedds_laptop.xml" << EOF
<?xml version="1.0" encoding="UTF-8" ?>
<!--
  CycloneDDS Configuration for LAPTOP (Ground Station)
  Generated: $(date)
  
  Copy this file to your laptop: ~/cyclonedds_laptop.xml
  Then set: export CYCLONEDDS_URI=file:///home/YOUR_USER/cyclonedds_laptop.xml
  
  KRIA Robot IP: $WIFI_IP
-->
<CycloneDDS xmlns="https://cdds.io/config"
            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xsi:schemaLocation="https://cdds.io/config https://raw.githubusercontent.com/eclipse-cyclonedds/cyclonedds/master/etc/cyclonedds.xsd">
  <Domain id="any">
    <General>
      <!-- Bind to WiFi interface only (adjust if needed: wlp3s0, wlan0, etc) -->
      <Interfaces>
        <NetworkInterface name="wlp3s0" priority="default" multicast="true" />
      </Interfaces>
      <AllowMulticast>spdp</AllowMulticast>
    </General>
    <Discovery>
      <!-- Unicast peer discovery: KRIA Robot + localhost -->
      <Peers>
        <Peer address="$WIFI_IP"/>
        <Peer address="localhost"/>
      </Peers>
      <ParticipantIndex>auto</ParticipantIndex>
      <MaxAutoParticipantIndex>120</MaxAutoParticipantIndex>
    </Discovery>
    <Internal>
      <SocketReceiveBufferSize min="default"/>
    </Internal>
  </Domain>
</CycloneDDS>
EOF

echo -e "${GREEN}✓ Created: $CONFIG_DIR/cyclonedds_laptop.xml${NC}"

# =========================================
# Update setup script
# =========================================

cat > "$SCRIPT_DIR/../setup_dds_wifi.sh" << EOF
#!/bin/bash
# =============================================================
# Setup script for ROS2 DDS communication over WiFi
# Run this on KRIA before launching ROS2 nodes
# Usage: source setup_dds_wifi.sh
# =============================================================

SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"

# Set CycloneDDS as RMW implementation
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp

# Point to WiFi-configured CycloneDDS config
export CYCLONEDDS_URI="file://\${SCRIPT_DIR}/config/cyclonedds.xml"

# ROS2 Domain ID (must match on laptop)
export ROS_DOMAIN_ID=30
export ROS_LOCALHOST_ONLY=0

# Display current config
echo "[DDS Setup - KRIA WiFi Mode]"
echo "  RMW_IMPLEMENTATION = \$RMW_IMPLEMENTATION"
echo "  CYCLONEDDS_URI     = \$CYCLONEDDS_URI"
echo "  ROS_DOMAIN_ID      = \$ROS_DOMAIN_ID"
echo "  Network interface  = $INTERFACE_CONFIG"
echo "  KRIA IP            = $WIFI_IP"
echo "  Laptop IP          = $LAPTOP_IP"
echo ""
echo "Ready to launch ROS2 nodes over WiFi."
EOF

chmod +x "$SCRIPT_DIR/../setup_dds_wifi.sh"
echo -e "${GREEN}✓ Created: setup_dds_wifi.sh${NC}"

# =========================================
# Summary
# =========================================

echo ""
echo "=============================================="
echo "                 SUMMARY"
echo "=============================================="
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  CycloneDDS WiFi Config Complete!         ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════╝${NC}"
echo ""
echo "Files created/updated:"
echo "  • $CONFIG_DIR/cyclonedds.xml"
echo "  • $CONFIG_DIR/cyclonedds_laptop.xml"
echo "  • $SCRIPT_DIR/../setup_dds_wifi.sh"
echo ""
echo "─────────────────────────────────────────────"
echo "NEXT STEPS:"
echo "─────────────────────────────────────────────"
echo ""
echo "1. On KRIA (before launching ROS2):"
echo "   cd $WORKSPACE_DIR"
echo "   source src/lidar_spatial_filter/setup_dds_wifi.sh"
echo ""
echo "2. Copy laptop config to your laptop:"
echo "   scp $CONFIG_DIR/cyclonedds_laptop.xml user@laptop:~/"
echo ""
echo "3. On LAPTOP (before launching ROS2):"
echo "   export CYCLONEDDS_URI=file://~/cyclonedds_laptop.xml"
echo "   export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp"
echo "   export ROS_DOMAIN_ID=30"
echo ""
echo "4. Test with:"
echo "   ./04_test_ros2.sh"
echo ""
