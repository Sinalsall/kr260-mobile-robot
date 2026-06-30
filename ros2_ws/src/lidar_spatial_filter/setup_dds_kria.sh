#!/bin/bash
# =============================================================
# Setup script for ROS2 DDS communication with Cloudflare WARP
# Run this on KRIA before launching ROS2 nodes
# Usage: source setup_dds.sh
# =============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set CycloneDDS as RMW implementation
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp

# Point to our custom CycloneDDS config that binds to eth1 only
export CYCLONEDDS_URI="file://${SCRIPT_DIR}/config/cyclonedds.xml"

# ROS2 Domain ID (must match on laptop)
export ROS_DOMAIN_ID=30
export ROS_LOCALHOST_ONLY=0

echo "[DDS Setup - KRIA]"
echo "  RMW_IMPLEMENTATION = $RMW_IMPLEMENTATION"
echo "  CYCLONEDDS_URI     = $CYCLONEDDS_URI"
echo "  ROS_DOMAIN_ID      = $ROS_DOMAIN_ID"
echo "  Network interface   = eth1 (192.168.0.x)"
echo ""
echo "Ready to launch ROS2 nodes."
