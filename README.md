# KR260 Mobile Robot — ROS 2 + FPGA Hardware Acceleration

Sistem navigasi otonom untuk mobile robot indoor berbasis **AMD Kria KR260**, mengintegrasikan **ROS 2 Humble** pada Processing System (PS) dengan **FPGA Programmable Logic (PL)** untuk akselerasi pemrosesan LiDAR dan path planning.

## Directory Structure

```
kr260-mobile-robot/
├── README.md
├── startup_sequence.md                # Complete terminal startup sequence
├── ros2_ws/
│   ├── src/
│   │   ├── mobile_robot_pkg/          # Computing unit + control unit
│   │   ├── lidar_pl_accel/            # PS-PL LiDAR processing (C++)
│   │   ├── lidar_spatial_filter/      # SW baseline LiDAR + config + custom msgs
│   │   ├── robot_web_ui/              # Web UI monitoring (Python)
│   │   └── dxl_serial_bridge/         # Dynamixel actuator bridge
│   └── config/
│       ├── cyclonedds.xml             # CycloneDDS DDS config (KRIA)
│       ├── cyclonedds_laptop_template.xml  # DDS config (laptop template)
│       └── lidar_filter_params.yaml   # LiDAR processing parameters
├── fpga/
│   ├── hls/
│   │   ├── lidar_hw_filter.cpp        # Vitis HLS kernel source
│   │   └── build_hls.tcl              # HLS build script
│   ├── vivado/
│   │   └── add_ip.tcl                 # Vivado BD integration script
│   └── firmware/
│       ├── kr260_lidar_garis_astar_fw.dtsi  # Device tree overlay
│       └── shell.json                      # Firmware descriptor (XRT_FLAT)
├── maps/
│   └── map.json                       # Grid map (40x40, 5cm cell)
├── docs/
│   ├── architecture.md                # System architecture details
│   ├── ps_pl_partition.md             # PS vs PL partition table
│   └── register_map.md                # AXI4-Lite register map
└── .gitignore
```

---

## Prerequisites

### Hardware
- AMD Kria KR260 Robotics Starter Kit (xck26-sfvc784-2LV-c)
- RPLiDAR A2M8 (2D laser scanner)
- TP-Link TL-WN725N WiFi nano adapter (RTL8188EUS)
- Dynamixel XL330-M288-T servo (actuator)

### Software (local development)
- Vitis HLS 2024.1
- Vivado 2024.1
- ROS 2 Humble (cross-compiled for ARM64 or built on KRIA)

### Third-party ROS 2 packages (install separately)
- [sllidar_ros2](https://github.com/Slamtec/sllidar_ros2) — RPLiDAR A2M8 driver
- [udmabuf](https://github.com/ikwzm/udmabuf) — User-space DMA buffer kernel module

---

## Quick Start

See [startup_sequence.md](startup_sequence.md) for the complete terminal sequence.

### Hardware Setup (once per boot)
```bash
sudo insmod /home/ubuntu/udmabuf/u-dma-buf.ko
sudo xmutil loadapp kr260_lidar_garis_astar_fw
sudo chmod 666 /dev/uio* /dev/udmabuf*
```

### Build ROS 2 Workspace
```bash
cd ~/kria_ros2_ws
colcon build --merge-install --symlink-install
source install/setup.bash
```

### Launch Nodes (5 terminals)
```bash
# Terminal 1: LiDAR driver
ros2 launch sllidar_ros2 sllidar_a2m8_launch.py

# Terminal 2: LiDAR PS-PL processing
ros2 run lidar_pl_accel lidar_pl_node

# Terminal 3: Computing unit (A* + navigation)
ros2 launch mobile_robot_pkg bringup.launch.py

# Terminal 4: Control unit (motor control)
ros2 run mobile_robot_pkg control_unit

# Terminal 5: Web UI
ros2 run robot_web_ui web_ui_node
```

### Access Web UI
Browser on laptop:
```
http://<kria-ip>:8080/
```

---

## LiDAR Processing Pipeline

| Stage | Location | Description |
|-------|----------|-------------|
| Receive LaserScan | PS | ROS 2 subscriber |
| Configure parameters | PS | Write angle, ROI, filter range to IP registers |
| Transfer data | PS | memcpy ranges to udmabuf TX, trigger DMA |
| **Filtering** | PL | Select points within valid range [0.15, 3.0] m |
| **Polar to Cartesian** | PL | x = r*cos(a), y = r*sin(a) via HLS floating-point |
| **ROI Classification** | PL | Label 1=obstacle (inside trapezoid), 2=landmark, 0=ignored |
| Clustering | PS | Sequential radial clustering (O(n), streaming-friendly) |
| Validation + Safety | PS | Nearest distance, emergency stop (< 0.20 m) |
| Publish results | PS | ROS 2 topics: obstacle points, nearest distance, e-stop |

---

## FPGA Resources (lidar_hw_filter)

| Resource | Used | Available | Utilization |
|----------|------|-----------|:-----------:|
| LUT | 7,764 | 117,120 | 6.63% |
| DSP | 42 | 1,248 | 3.69% |
| BRAM | 0 | 144 | 0% |

Timing: WNS 1.25 ns (clock 100 MHz met with margin)

---

## Key Results

- LiDAR accuracy: galat -3.23% to +2.56% across 15 measurement points (0.2m - 5.3m)
- PS-PL processing time: 0.98 ms per frame (vs 1.37 ms PS-only baseline)
- PL-only compute: 14.6 us for 1,454 points (II=1 pipeline)
- Emergency stop verified at < 0.20 m threshold
- Web UI real-time telemetry via SSE (server-sent events), no ROS 2 required on laptop
- Network: WiFi static IP + CycloneDDS (domain 30) + Tailscale remote access
- Total FPGA utilization: 10.85% LUT, 9.03% BRAM, 3.69% DSP

---

## Authors

John Sinalsal Saragih (13222058) - Institut Teknologi Bandung

Pembimbing: Anggera Bayuwindra, S.T., M.T., Ph.D. | Nana Sutisna, S.T., M.T., Ph.D.

---

## License

MIT
