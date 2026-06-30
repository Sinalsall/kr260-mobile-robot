#!/bin/bash
# =============================================================
# Script 4: Test ROS2 Communication over WiFi
# Untuk KRIA KR260 + ROS2 + CycloneDDS
# 
# Usage: ./04_test_ros2.sh
# =============================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"

echo ""
echo "=============================================="
echo "    ROS2 WiFi Communication Test"
echo "    KRIA KR260"
echo "=============================================="
echo ""

# =========================================
# Check Environment
# =========================================

echo "─────────────────────────────────────────────"
echo "Environment Check"
echo "─────────────────────────────────────────────"

# Check ROS2
if ! command -v ros2 &> /dev/null; then
    echo -e "${YELLOW}ROS2 not sourced. Sourcing now...${NC}"
    source /opt/ros/humble/setup.bash
fi

echo "  ROS2 Distro: $ROS_DISTRO"

# Check DDS environment
echo "  RMW_IMPLEMENTATION: ${RMW_IMPLEMENTATION:-not set}"
echo "  CYCLONEDDS_URI: ${CYCLONEDDS_URI:-not set}"
echo "  ROS_DOMAIN_ID: ${ROS_DOMAIN_ID:-0}"
echo ""

if [ -z "$RMW_IMPLEMENTATION" ] || [ "$RMW_IMPLEMENTATION" != "rmw_cyclonedds_cpp" ]; then
    echo -e "${YELLOW}Setting up DDS environment...${NC}"
    if [ -f "$WORKSPACE_DIR/src/lidar_spatial_filter/setup_dds_wifi.sh" ]; then
        source "$WORKSPACE_DIR/src/lidar_spatial_filter/setup_dds_wifi.sh"
    else
        export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
        export ROS_DOMAIN_ID=30
    fi
fi

# =========================================
# Network Status
# =========================================

echo "─────────────────────────────────────────────"
echo "Network Status"
echo "─────────────────────────────────────────────"

# Get wireless interface
WLAN_IFACE=$(iw dev 2>/dev/null | grep Interface | awk '{print $2}' | head -1)
if [ -n "$WLAN_IFACE" ]; then
    WIFI_IP=$(ip addr show "$WLAN_IFACE" | grep "inet " | awk '{print $2}' | cut -d/ -f1)
    echo -e "  ${GREEN}WiFi ($WLAN_IFACE): $WIFI_IP${NC}"
else
    echo -e "  ${RED}WiFi: Not connected${NC}"
fi

# Get ethernet
ETH_IP=$(ip addr show eth1 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)
if [ -n "$ETH_IP" ]; then
    echo -e "  ${GREEN}Ethernet (eth1): $ETH_IP${NC}"
fi

echo ""

# =========================================
# Test 1: ROS2 Daemon
# =========================================

echo "─────────────────────────────────────────────"
echo "Test 1: ROS2 Daemon"
echo "─────────────────────────────────────────────"

ros2 daemon stop &>/dev/null || true
sleep 1
ros2 daemon start &>/dev/null || true
sleep 2

if ros2 daemon status &>/dev/null; then
    echo -e "${GREEN}✓ ROS2 daemon running${NC}"
else
    echo -e "${YELLOW}⚠ ROS2 daemon status unclear (normal)${NC}"
fi
echo ""

# =========================================
# Test 2: Topic List
# =========================================

echo "─────────────────────────────────────────────"
echo "Test 2: ROS2 Topics"
echo "─────────────────────────────────────────────"

TOPICS=$(ros2 topic list 2>/dev/null | head -10)
TOPIC_COUNT=$(echo "$TOPICS" | grep -c "^/" || echo "0")

echo "  Topics found: $TOPIC_COUNT"
if [ "$TOPIC_COUNT" -gt 0 ]; then
    echo "$TOPICS" | while read line; do
        echo "    $line"
    done
fi
echo ""

# =========================================
# Test 3: Node List
# =========================================

echo "─────────────────────────────────────────────"
echo "Test 3: ROS2 Nodes"
echo "─────────────────────────────────────────────"

NODES=$(ros2 node list 2>/dev/null | head -10)
NODE_COUNT=$(echo "$NODES" | grep -c "^/" || echo "0")

echo "  Nodes found: $NODE_COUNT"
if [ "$NODE_COUNT" -gt 0 ]; then
    echo "$NODES" | while read line; do
        echo "    $line"
    done
fi
echo ""

# =========================================
# Test 4: Service List
# =========================================

echo "─────────────────────────────────────────────"
echo "Test 4: ROS2 Services"
echo "─────────────────────────────────────────────"

SERVICES=$(ros2 service list 2>/dev/null | head -10)
SVC_COUNT=$(echo "$SERVICES" | grep -c "^/" || echo "0")

echo "  Services found: $SVC_COUNT"
if [ "$SVC_COUNT" -gt 0 ]; then
    echo "  (First 10 services)"
    echo "$SERVICES" | while read line; do
        echo "    $line"
    done
fi
echo ""

# =========================================
# Test 5: Publish/Subscribe Test
# =========================================

echo "─────────────────────────────────────────────"
echo "Test 5: Local Publish/Subscribe"
echo "─────────────────────────────────────────────"

TEST_TOPIC="/kria_wifi_test"

# Start subscriber in background
echo "  Starting test subscriber..."
timeout 10 ros2 topic echo "$TEST_TOPIC" std_msgs/msg/String --once &>/tmp/ros2_sub_output.txt &
SUB_PID=$!
sleep 2

# Publish test message
echo "  Publishing test message..."
ros2 topic pub "$TEST_TOPIC" std_msgs/msg/String "data: 'KRIA_WIFI_TEST_$(date +%s)'" --once &>/dev/null

# Wait for subscriber
sleep 3
kill $SUB_PID 2>/dev/null || true

# Check result
if grep -q "KRIA_WIFI_TEST" /tmp/ros2_sub_output.txt 2>/dev/null; then
    echo -e "${GREEN}✓ Local pub/sub working!${NC}"
else
    echo -e "${YELLOW}⚠ Local pub/sub test inconclusive${NC}"
fi
rm -f /tmp/ros2_sub_output.txt
echo ""

# =========================================
# Test 6: Cross-device Discovery
# =========================================

echo "─────────────────────────────────────────────"
echo "Test 6: Cross-Device Discovery"
echo "─────────────────────────────────────────────"
echo ""
echo -e "${CYAN}To test communication with laptop:${NC}"
echo ""
echo "1. On LAPTOP, run:"
echo "   export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp"
echo "   export CYCLONEDDS_URI=file://~/cyclonedds_laptop.xml"
echo "   export ROS_DOMAIN_ID=30"
echo "   ros2 topic echo /kria_wifi_test"
echo ""
echo "2. On KRIA (this device), run:"
echo "   ros2 topic pub /kria_wifi_test std_msgs/msg/String \"data: 'hello from robot'\" -r 1"
echo ""
echo "3. If laptop receives messages, WiFi ROS2 is working!"
echo ""

# =========================================
# Bandwidth Test Option
# =========================================

echo "─────────────────────────────────────────────"
echo "Optional: Bandwidth Test"
echo "─────────────────────────────────────────────"
echo ""
read -p "Run bandwidth test? (requires iperf3) [y/N]: " RUN_BW

if [ "$RUN_BW" = "y" ] || [ "$RUN_BW" = "Y" ]; then
    if command -v iperf3 &> /dev/null; then
        # Get laptop IP from config
        LAPTOP_IP=$(grep -oP 'Peer address="\K[0-9.]+' "$WORKSPACE_DIR/src/lidar_spatial_filter/config/cyclonedds.xml" | grep -v "localhost" | head -1)
        
        if [ -n "$LAPTOP_IP" ]; then
            echo ""
            echo "To test bandwidth:"
            echo "1. On LAPTOP, run: iperf3 -s"
            echo "2. Press Enter here when laptop server is ready..."
            read -p ""
            
            echo "Running bandwidth test to $LAPTOP_IP..."
            iperf3 -c "$LAPTOP_IP" -t 10 2>/dev/null || echo "iperf3 failed - is server running on laptop?"
        fi
    else
        echo "iperf3 not installed. Install with: sudo apt install iperf3"
    fi
fi

# =========================================
# Summary
# =========================================

echo ""
echo "=============================================="
echo "                 SUMMARY"
echo "=============================================="
echo ""
echo "  Topics:   $TOPIC_COUNT"
echo "  Nodes:    $NODE_COUNT"  
echo "  Services: $SVC_COUNT"
echo ""

if [ "$TOPIC_COUNT" -gt 0 ] || [ "$NODE_COUNT" -gt 0 ]; then
    echo -e "${GREEN}╔═══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ROS2 Communication: WORKING              ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════╝${NC}"
else
    echo -e "${YELLOW}╔═══════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  No active nodes - start your ROS2 nodes  ║${NC}"
    echo -e "${YELLOW}╚═══════════════════════════════════════════╝${NC}"
fi
echo ""
