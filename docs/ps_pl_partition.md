# PS-PL Partition

Pembagian fungsi pemrosesan LiDAR antara Processing System (PS) dan Programmable Logic (PL).

| Stage | Location | Description |
|-------|----------|-------------|
| Penerimaan LaserScan | **PS** | ROS 2 subscriber callback dari topic /scan |
| Konfigurasi parameter | **PS** | Menulis angle, ROI, filter range ke register IP via AXI4-Lite |
| Transfer data range | **PS** | memcpy ranges.data() ke udmabuf TX, trigger DMA |
| **Filtering jarak** | **PL** | Memilih titik dalam rentang valid [0.15, 3.0] m |
| **Konversi polar-kartesian** | **PL** | x = r*cos(a), y = r*sin(a) via hls::cos/hls::sin |
| **Klasifikasi ROI** | **PL** | Label 1=obstacle (dalam trapezoid), 2=landmark, 0=ignored |
| Kirim hasil + EOF | **PL** | 128-bit output: x[31:0], y[63:32], label[95:64], EOF = label 99 |
| Clustering titik obstacle | **PS** | Sequential radial clustering (O(n), streaming-friendly) |
| Validasi obstacle + safety | **PS** | Menghitung jarak obstacle terdekat, status emergency stop |
| Publikasi topic ROS 2 | **PS** | /navigation/obstacle_points, /obstacle_nearest_distance, /emergency_stop |

## Rationale

- **PL** handles repetitive per-point operations (filtering, math, classification) with deterministic timing via II=1 pipeline
- **PS** retains high-level decision logic (clustering, validation) where software flexibility is needed
- DMA transfers entire scan frame in single burst, minimizing PS intervention
- PL compute time: 14.6 us for 1,454 points (vs 1.37 ms total for PS-only baseline)
