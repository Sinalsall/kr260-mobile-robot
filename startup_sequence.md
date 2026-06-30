# Hardware Setup (fresh boot, run ONCE)

```bash
# Terminal 0 — Hardware
sudo insmod /home/ubuntu/udmabuf/u-dma-buf.ko
sudo xmutil loadapp kr260_lidar_garis_astar_fw
sudo chmod 666 /dev/uio* /dev/udmabuf*
```

# Verify

```bash
# Check UIO devices
cat /sys/class/uio/uio*/name
# Expected: dma, lidar_hw_filter, astar

# Check udmabuf
ls /dev/udmabuf*
# Expected: /dev/udmabuf, /dev/udmabuf0
```

# Build (run after code changes)

```bash
cd ~/kria_ros2_ws
sudo rm -rf install build
colcon build --merge-install --symlink-install
```

# Terminal 1 — LiDAR Driver

```bash
cd ~/kria_ros2_ws && source install/setup.bash
ros2 launch sllidar_ros2 sllidar_a2m8_launch.py
```

Publishes: /scan (sensor_msgs/LaserScan)

# Terminal 2 — LiDAR PS-PL Hardware Processing

```bash
sudo chmod 666 /dev/uio* /dev/udmabuf*
cd ~/kria_ros2_ws && source install/setup.bash
ros2 run lidar_pl_accel lidar_pl_node
```

Subscribes: /scan
Publishes: /obstacle_boxes, /obstacle_nearest_distance, /emergency_stop,
           /navigation/obstacle_points, /navigation/roi_classification

# Terminal 3 — Computing Unit (A* Path Planning)

```bash
cd ~/kria_ros2_ws && source install/setup.bash
ros2 launch mobile_robot_pkg bringup.launch.py
```

Subscribes: /start_finish_command, /dynamixel_feedback,
            /navigation/obstacle_points, /obstacle_nearest_distance, /emergency_stop
Publishes: /robot_velocity_command, /planning_status

# Terminal 4 — Control Unit (Motor Control)

```bash
cd ~/kria_ros2_ws && source install/setup.bash
ros2 run mobile_robot_pkg control_unit
```

Subscribes: /robot_velocity_command
Publishes: /dynamixel_feedback

# Terminal 5 — Web UI (Monitoring)

```bash
cd ~/kria_ros2_ws && source install/setup.bash
ros2 run robot_web_ui web_ui_node
```

Subscribes: /planning_status, /dynamixel_feedback, /robot_velocity_command,
            /navigation/obstacle_points, /obstacle_nearest_distance, /emergency_stop
Publishes: /start_finish_command

# Laptop — SSH Tunnel for Web UI

```bash
ssh -L 8080:127.0.0.1:8080 ubuntu@100.76.130.74
```

Browser: http://localhost:8080/

---

# Network Setup (WiFi + CycloneDDS)

```bash
# Before launching any ROS 2 nodes
source ~/kria_ros2_ws/src/lidar_spatial_filter/config/setup_dds_wifi.sh

# Export manually if script not found
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export CYCLONEDDS_URI="file:///path/to/cyclonedds.xml"
export ROS_DOMAIN_ID=30
export ROS_LOCALHOST_ONLY=0
```

# Troubleshooting

**udmabuf0 not found:**
```bash
sudo insmod /home/ubuntu/udmabuf/u-dma-buf.ko
# Must run BEFORE xmutil loadapp
```

**Firmware load Error -1:**
Ensure firmware directory has exactly 4 files (.bit.bin, .dtbo, .dtsi, shell.json).
Remove any extra files like primary.bit or subfolders.

**map.json not found:**
Use `ros2 launch mobile_robot_pkg bringup.launch.py` instead of `ros2 run`.
The launch file sets the absolute map path.

**Permission denied on /dev/uio:**
```bash
sudo chmod 666 /dev/uio* /dev/udmabuf*
```
