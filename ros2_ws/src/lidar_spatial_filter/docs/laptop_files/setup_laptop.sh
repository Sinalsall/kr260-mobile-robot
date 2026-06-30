#!/bin/bash
# =============================================================
# Laptop Setup Script untuk komunikasi dengan KRIA Robot
# 
# INSTRUKSI:
# 1. Copy script ini ke laptop Anda
# 2. Copy juga file cyclonedds_laptop.xml ke ~/
# 3. Jalankan: chmod +x setup_laptop.sh && ./setup_laptop.sh
# =============================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}=============================================="
echo "    Laptop Setup for KRIA Robot Communication"
echo "    ROS2 Humble + CycloneDDS"
echo "==============================================${NC}"
echo ""

# =========================================
# Check Prerequisites
# =========================================

echo -e "${BLUE}[1/6] Checking prerequisites...${NC}"

# Check ROS2
if [ -f /opt/ros/humble/setup.bash ]; then
    source /opt/ros/humble/setup.bash
    echo -e "  ${GREEN}✓ ROS2 Humble found${NC}"
else
    echo -e "  ${RED}✗ ROS2 Humble not found!${NC}"
    echo "    Please install ROS2 Humble first"
    exit 1
fi

# Check CycloneDDS
if ros2 pkg list 2>/dev/null | grep -q rmw_cyclonedds; then
    echo -e "  ${GREEN}✓ CycloneDDS package found${NC}"
else
    echo -e "  ${YELLOW}⚠ CycloneDDS not found, installing...${NC}"
    sudo apt update
    sudo apt install -y ros-humble-rmw-cyclonedds-cpp
fi

echo ""

# =========================================
# Check/Create Config File
# =========================================

echo -e "${BLUE}[2/6] Checking CycloneDDS config...${NC}"

CONFIG_FILE="$HOME/cyclonedds_laptop.xml"

if [ -f "$CONFIG_FILE" ]; then
    echo -e "  ${GREEN}✓ Config file found: $CONFIG_FILE${NC}"
else
    echo -e "  ${YELLOW}⚠ Config file not found!${NC}"
    echo ""
    echo "  Anda perlu mendapatkan file cyclonedds_laptop.xml dari KRIA."
    echo ""
    echo "  Opsi 1 - SCP dari KRIA:"
    echo "    scp ubuntu@192.168.0.100:~/kria_ros2_ws/src/lidar_spatial_filter/config/cyclonedds_laptop.xml ~/"
    echo ""
    echo "  Opsi 2 - Buat config default sekarang?"
    read -p "  Buat config default? [y/N]: " CREATE_DEFAULT
    
    if [ "$CREATE_DEFAULT" = "y" ] || [ "$CREATE_DEFAULT" = "Y" ]; then
        # Detect WiFi interface
        WIFI_IFACE=$(ip link show | grep -oP 'wl[a-z0-9]+' | head -1)
        WIFI_IFACE="${WIFI_IFACE:-wlp3s0}"
        
        read -p "  WiFi interface [$WIFI_IFACE]: " CUSTOM_IFACE
        WIFI_IFACE="${CUSTOM_IFACE:-$WIFI_IFACE}"
        
        read -p "  KRIA IP address [192.168.0.100]: " KRIA_IP
        KRIA_IP="${KRIA_IP:-192.168.0.100}"
        
        cat > "$CONFIG_FILE" << EOF
<?xml version="1.0" encoding="UTF-8" ?>
<CycloneDDS xmlns="https://cdds.io/config"
            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xsi:schemaLocation="https://cdds.io/config https://raw.githubusercontent.com/eclipse-cyclonedds/cyclonedds/master/etc/cyclonedds.xsd">
  <Domain id="any">
    <General>
      <Interfaces>
        <NetworkInterface name="$WIFI_IFACE" priority="default" multicast="true" />
      </Interfaces>
      <AllowMulticast>spdp</AllowMulticast>
    </General>
    <Discovery>
      <Peers>
        <Peer address="$KRIA_IP"/>
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
        echo -e "  ${GREEN}✓ Config file created: $CONFIG_FILE${NC}"
    else
        echo "  Please get the config file from KRIA and run this script again."
        exit 1
    fi
fi

echo ""

# =========================================
# Detect WiFi Interface
# =========================================

echo -e "${BLUE}[3/6] Detecting WiFi interface...${NC}"

WIFI_IFACE=$(ip link show | grep -oP 'wl[a-z0-9]+' | head -1)

if [ -n "$WIFI_IFACE" ]; then
    WIFI_IP=$(ip addr show "$WIFI_IFACE" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)
    echo -e "  ${GREEN}✓ WiFi interface: $WIFI_IFACE${NC}"
    echo -e "  ${GREEN}✓ WiFi IP: $WIFI_IP${NC}"
    
    # Check if config matches
    CONFIG_IFACE=$(grep -oP 'NetworkInterface name="\K[^"]+' "$CONFIG_FILE" | head -1)
    if [ "$CONFIG_IFACE" != "$WIFI_IFACE" ]; then
        echo -e "  ${YELLOW}⚠ Config says '$CONFIG_IFACE' but your interface is '$WIFI_IFACE'${NC}"
        read -p "  Update config file? [Y/n]: " UPDATE_CONFIG
        if [ "$UPDATE_CONFIG" != "n" ] && [ "$UPDATE_CONFIG" != "N" ]; then
            sed -i "s/NetworkInterface name=\"$CONFIG_IFACE\"/NetworkInterface name=\"$WIFI_IFACE\"/" "$CONFIG_FILE"
            echo -e "  ${GREEN}✓ Config updated${NC}"
        fi
    fi
else
    echo -e "  ${RED}✗ No WiFi interface found!${NC}"
    echo "    Make sure WiFi is enabled and connected"
fi

echo ""

# =========================================
# Create Setup Script
# =========================================

echo -e "${BLUE}[4/6] Creating setup script...${NC}"

SETUP_SCRIPT="$HOME/setup_ros2_kria.sh"

cat > "$SETUP_SCRIPT" << 'EOF'
#!/bin/bash
# Setup ROS2 komunikasi dengan KRIA Robot
# Usage: source ~/setup_ros2_kria.sh

# Source ROS2
source /opt/ros/humble/setup.bash

# Source workspace jika ada
if [ -f ~/ros2_ws/install/setup.bash ]; then
    source ~/ros2_ws/install/setup.bash
fi
if [ -f ~/catkin_ws/install/setup.bash ]; then
    source ~/catkin_ws/install/setup.bash
fi

# CycloneDDS config
export CYCLONEDDS_URI=file://$HOME/cyclonedds_laptop.xml
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export ROS_DOMAIN_ID=30
export ROS_LOCALHOST_ONLY=0

echo "[ROS2 KRIA Setup - Laptop]"
echo "  RMW_IMPLEMENTATION = $RMW_IMPLEMENTATION"
echo "  CYCLONEDDS_URI     = $CYCLONEDDS_URI"
echo "  ROS_DOMAIN_ID      = $ROS_DOMAIN_ID"
echo ""
echo "Ready to communicate with KRIA robot!"
echo "  ros2 topic list    - lihat topics"
echo "  ros2 node list     - lihat nodes"
echo "  ros2 service list  - lihat services"
EOF

chmod +x "$SETUP_SCRIPT"
echo -e "  ${GREEN}✓ Created: $SETUP_SCRIPT${NC}"

echo ""

# =========================================
# Add to bashrc (optional)
# =========================================

echo -e "${BLUE}[5/6] Bashrc configuration...${NC}"

if grep -q "setup_ros2_kria.sh" ~/.bashrc 2>/dev/null; then
    echo -e "  ${GREEN}✓ Already in ~/.bashrc${NC}"
else
    read -p "  Add to ~/.bashrc for auto-setup? [y/N]: " ADD_BASHRC
    if [ "$ADD_BASHRC" = "y" ] || [ "$ADD_BASHRC" = "Y" ]; then
        echo "" >> ~/.bashrc
        echo "# KRIA Robot ROS2 Setup" >> ~/.bashrc
        echo "source ~/setup_ros2_kria.sh" >> ~/.bashrc
        echo -e "  ${GREEN}✓ Added to ~/.bashrc${NC}"
    else
        echo "  Skipped. Run 'source ~/setup_ros2_kria.sh' manually each time."
    fi
fi

echo ""

# =========================================
# Test Connection
# =========================================

echo -e "${BLUE}[6/6] Testing connection...${NC}"

# Get KRIA IP from config
KRIA_IP=$(grep -oP 'Peer address="\K[0-9.]+' "$CONFIG_FILE" | grep -v "localhost" | head -1)
KRIA_IP="${KRIA_IP:-192.168.0.100}"

echo "  Testing connection to KRIA ($KRIA_IP)..."

if ping -c 2 -W 2 "$KRIA_IP" &>/dev/null; then
    echo -e "  ${GREEN}✓ KRIA is reachable!${NC}"
else
    echo -e "  ${YELLOW}⚠ Cannot ping KRIA at $KRIA_IP${NC}"
    echo "    - Make sure KRIA is powered on"
    echo "    - Make sure both devices are on same WiFi network"
    echo "    - Check KRIA IP address"
fi

echo ""

# =========================================
# Summary
# =========================================

echo -e "${GREEN}=============================================="
echo "              SETUP COMPLETE!"
echo "==============================================${NC}"
echo ""
echo "Files created:"
echo "  • $CONFIG_FILE"
echo "  • $SETUP_SCRIPT"
echo ""
echo "To start using:"
echo -e "  ${CYAN}source ~/setup_ros2_kria.sh${NC}"
echo ""
echo "Then test with:"
echo "  ros2 topic list"
echo "  ros2 node list"
echo "  ros2 service list"
echo ""
echo "KRIA IP: $KRIA_IP"
echo "WiFi Interface: $WIFI_IFACE"
echo ""
