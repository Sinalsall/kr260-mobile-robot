#!/bin/bash
# ═══════════════════════════════════════════════════════════
# Automatic Laptop Setup for ROS2 WiFi Communication
# Copy dan jalankan script ini di LAPTOP
# ═══════════════════════════════════════════════════════════

set -e

echo "╔═══════════════════════════════════════════════════════╗"
echo "║  ROS2 WiFi Setup - LAPTOP (Ground Station)           ║"
echo "║  KRIA Robot Communication                             ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""

# ─────────────────────────────────────────────────────────
# STEP 1: Check ROS2 Installation
# ─────────────────────────────────────────────────────────
echo "[1/5] Checking ROS2 installation..."
if [ -f "/opt/ros/humble/setup.bash" ]; then
    source /opt/ros/humble/setup.bash
    echo "  ✓ ROS2 Humble found"
elif [ -f "/opt/ros/foxy/setup.bash" ]; then
    source /opt/ros/foxy/setup.bash
    echo "  ✓ ROS2 Foxy found"
else
    echo "  ✗ ERROR: ROS2 not found!"
    echo "    Please install ROS2 first"
    exit 1
fi

# ─────────────────────────────────────────────────────────
# STEP 2: Check CycloneDDS Installation
# ─────────────────────────────────────────────────────────
echo ""
echo "[2/5] Checking CycloneDDS..."
if dpkg -l | grep -q "ros-$ROS_DISTRO-rmw-cyclonedds-cpp"; then
    echo "  ✓ CycloneDDS installed"
else
    echo "  ✗ CycloneDDS not installed"
    echo "  Installing now..."
    sudo apt update
    sudo apt install -y ros-$ROS_DISTRO-rmw-cyclonedds-cpp
    echo "  ✓ CycloneDDS installed successfully"
fi

# ─────────────────────────────────────────────────────────
# STEP 3: Detect WiFi Interface
# ─────────────────────────────────────────────────────────
echo ""
echo "[3/5] Detecting WiFi interface..."
WIFI_IFACE="tailscale0" # $(ip -o link show | grep -i "state UP" | grep -iE "wl|wlan" | awk '{print $2}' | sed 's/:$//' | head -1)

if [ -z "$WIFI_IFACE" ]; then
    echo "  ⚠ No active WiFi interface detected"
    echo "  Available wireless interfaces:"
    ip link | grep -iE "wl|wlan" | awk '{print "    - "$2}' | sed 's/:$//'
    echo ""
    read -p "  Enter your WiFi interface name (e.g., wlp3s0): " WIFI_IFACE
    
    if [ -z "$WIFI_IFACE" ]; then
        echo "  ✗ No interface specified. Using default: wlp3s0"
        WIFI_IFACE="wlp3s0"
    fi
fi

echo "  ✓ Using interface: $WIFI_IFACE"

# ─────────────────────────────────────────────────────────
# STEP 4: Copy CycloneDDS Config
# ─────────────────────────────────────────────────────────
echo ""
echo "[4/5] Setting up CycloneDDS config..."

if [ ! -f "$HOME/cyclonedds_laptop.xml" ]; then
    echo "  ✗ Config file not found at: $HOME/cyclonedds_laptop.xml"
    echo ""
    echo "  Please copy the file from KRIA first:"
    echo "    scp ubuntu@192.168.0.100:~/kria_ros2_ws/src/lidar_spatial_filter/config/cyclonedds_laptop.xml ~/"
    echo "  OR via Tailscale:"
    echo "    scp ubuntu@100.76.130.74:~/kria_ros2_ws/src/lidar_spatial_filter/config/cyclonedds_laptop.xml ~/"
    exit 1
fi

# Update interface name in config if needed
sed -i "s/name=\"wlp3s0\"/name=\"$WIFI_IFACE\"/" "$HOME/cyclonedds_laptop.xml"
echo "  ✓ Config updated for interface: $WIFI_IFACE"

# ─────────────────────────────────────────────────────────
# STEP 5: Create Environment Setup Script
# ─────────────────────────────────────────────────────────
echo ""
echo "[5/5] Creating environment setup script..."

cat > "$HOME/setup_ros2_kria.sh" << 'INNER_EOF'
#!/bin/bash
# ROS2 Environment Setup for KRIA Robot Communication
# Usage: source ~/setup_ros2_kria.sh

# Source ROS2
if [ -f "/opt/ros/humble/setup.bash" ]; then
    source /opt/ros/humble/setup.bash
elif [ -f "/opt/ros/foxy/setup.bash" ]; then
    source /opt/ros/foxy/setup.bash
fi

# Setup CycloneDDS
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export CYCLONEDDS_URI=file://$HOME/cyclonedds_laptop.xml
export ROS_DOMAIN_ID=30
export ROS_LOCALHOST_ONLY=0

# Display configuration
echo "╔═══════════════════════════════════════════════════════╗"
echo "║  ROS2 Environment Ready - KRIA Robot Communication   ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""
echo "  ROS_DISTRO         = $ROS_DISTRO"
echo "  RMW_IMPLEMENTATION = $RMW_IMPLEMENTATION"
echo "  ROS_DOMAIN_ID      = $ROS_DOMAIN_ID"
echo "  CYCLONEDDS_URI     = $CYCLONEDDS_URI"
echo ""
echo "  KRIA Robot IP      = 192.168.0.100"
echo "  Tailscale IP       = 100.76.130.74"
echo ""
echo "Ready to communicate with KRIA robot!"
echo ""
INNER_EOF

chmod +x "$HOME/setup_ros2_kria.sh"
echo "  ✓ Created: $HOME/setup_ros2_kria.sh"

# ═══════════════════════════════════════════════════════════
# SETUP COMPLETE
# ═══════════════════════════════════════════════════════════
echo ""
echo "╔═══════════════════════════════════════════════════════╗"
echo "║  Setup Complete!                                      ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""
echo "Files created:"
echo "  • ~/cyclonedds_laptop.xml      (CycloneDDS config)"
echo "  • ~/setup_ros2_kria.sh         (Environment setup)"
echo ""
echo "─────────────────────────────────────────────────────────"
echo "HOW TO USE:"
echo "─────────────────────────────────────────────────────────"
echo ""
echo "1. SETIAP kali buka terminal baru, jalankan:"
echo "   source ~/setup_ros2_kria.sh"
echo ""
echo "2. Test komunikasi dengan KRIA:"
echo "   ros2 topic list"
echo "   ros2 node list"
echo ""
echo "3. Subscribe topic dari KRIA:"
echo "   ros2 topic echo /chatter"
echo ""
echo "4. Publish topic ke KRIA:"
echo "   ros2 topic pub /test std_msgs/String \"data: 'Hello KRIA'\""
echo ""
echo "─────────────────────────────────────────────────────────"
echo ""
