# System Architecture

## High-Level Architecture

```
+---------------------------+
|        User / Laptop      |
|   Browser (Web UI Port    |
|   8080) + ROS 2 Optional  |
+---------------------------+
              |
    WiFi / Tailscale VPN
              |
+----------------------------+
|      KRIA KR260             |
|                              |
|  PS (ARM Cortex-A53)          |
|  +--------------------------+|
|  | ROS 2 Humble              ||
|  | +------------------------+||
|  || /scan -> lidar_pl_node  |||
|  ||   -> computing_unit     |||
|  ||   -> control_unit       |||
|  ||   -> robot_web_ui       |||
|  |+------------------------+||
|  | PS-PL Interface (UIO)    ||
|  | dma_ptr, ip_ptr,         ||
|  | udmabuf_ptr              ||
|  +--------------------------+|
|                              |
|  PL (FPGA fabric)             |
|  +--------------------------+|
|  | AXI DMA (MM2S + S2MM)    ||
|  | lidar_hw_filter (HLS)    ||
|  | astar_kernel (HLS)       ||
|  +--------------------------+|
+----------------------------+
```

## Subsystem Components

### Sensing Unit
- RPLiDAR A2M8 laser scanner (360 degrees, 5.5 Hz rotation)
- Line sensor array (16 phototransistors, external platform)
- LiDAR HW filter IP on FPGA fabric

### Computing Unit
- A* path planning (SW reference + HW accelerated)
- Escape bubble mechanism for obstacle avoidance
- Local detour and global replanning on obstacle detection

### Control Unit
- PID-based line following with odometry feedback
- Dynamixel actuator RPM control
- Emergency stop handler

### User Interface
- Web UI running on KRIA (HTTP server + SSE)
- Real-time grid map with path overlay
- Live status panel (pose, velocity, RPM, obstacle distance, e-stop)

## Data Flow

```
RPLiDAR A2M8
    |
    v (/scan - LaserScan)
lidar_pl_node (PS-PL)
    | memcpy -> udmabuf TX
    | DMA TX -> FPGA
    v
lidar_hw_filter (PL)
    | pipeline II=1: filter -> polar2cart -> classify
    | DMA RX -> udmabuf RX
    v
lidar_pl_node (PS) reads results, clusters, validates
    |
    | Publish:
    |   /navigation/obstacle_points (PointCloud2)
    |   /obstacle_nearest_distance (Float32)
    |   /emergency_stop (Bool)
    v
computing_unit (A* planner)
    | A* search on grid with obstacles
    | Path -> velocity commands
    v
control_unit (motor)
    | PID line following + odometry
    v
Dynamixel motors (left/right RPM)
```

## UIO Device Mapping

| /dev/uio | Name | Address | Function |
|----------|------|---------|----------|
| uio0 | dma | 0xA0000000 | AXI DMA controller registers |
| uio1 | lidar_hw_filter | 0xB0000000 | LiDAR HLS IP registers |
| uio2 | astar | 0xA0020000 | A* HLS IP registers |
| udmabuf0 | udmabuf0 | DDR (8 MB) | Shared DMA buffer (TX+RX) |
