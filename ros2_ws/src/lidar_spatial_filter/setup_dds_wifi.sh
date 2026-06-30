#!/bin/bash
# =============================================================
# Setup script for ROS2 DDS communication over WiFi
# Run this on KRIA before launching ROS2 nodes
# Usage: source setup_dds_wifi.sh
# =============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set CycloneDDS as RMW implementation
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp

# Point to WiFi-configured CycloneDDS config
export CYCLONEDDS_URI="file://${SCRIPT_DIR}/config/cyclonedds.xml"

# ROS2 Domain ID (must match on laptop)
export ROS_DOMAIN_ID=30
export ROS_LOCALHOST_ONLY=0

# Display current config
echo "[DDS Setup - KRIA WiFi Mode]"
echo "  RMW_IMPLEMENTATION = $RMW_IMPLEMENTATION"
echo "  CYCLONEDDS_URI     = $CYCLONEDDS_URI"
echo "  ROS_DOMAIN_ID      = $ROS_DOMAIN_ID"
echo "  Network interface  = wlx6c4cbc88d820"
echo "  KRIA IP            = 192.168.0.100"
echo "  Laptop IP          = 192.168.0.104"
echo ""
echo "Ready to launch ROS2 nodes over WiFi."
