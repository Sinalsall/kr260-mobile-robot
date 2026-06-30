# WiFi Dongle Setup Guide untuk KRIA KR260
## TP-Link TL-WN725N + ROS2 + CycloneDDS

### Quick Start

```bash
# 1. Colok dongle ke USB port KRIA
# 2. Jalankan test dongle
cd ~/kria_ros2_ws/src/lidar_spatial_filter/scripts/wifi_setup
./01_test_dongle.sh

# 3. Setup WiFi connection
./02_setup_wifi.sh

# 4. Update CycloneDDS config
./03_setup_cyclonedds.sh

# 5. Test ROS2 communication
./04_test_ros2.sh
```

---

## Scripts yang Tersedia

### 1. `01_test_dongle.sh` - Test Compatibility
Cek apakah WiFi dongle terdeteksi dan compatible.

**Apa yang di-test:**
- USB detection (lsusb)
- Kernel driver loading
- Wireless interface creation
- WiFi scanning capability

**Expected output untuk TL-WN725N:**
```
[✓ PASS] TL-WN725N (RTL8188EUS) terdeteksi!
  Chipset: RTL8188EUS
  USB ID:  0bda:8179
```

### 2. `02_setup_wifi.sh` - Setup WiFi Connection
Konfigurasi koneksi WiFi dengan NetworkManager.

**Fitur:**
- Scan available networks
- Set static IP (recommended untuk ROS2)
- Auto-connect on boot
- Test connectivity

**Usage:**
```bash
# Interactive mode
./02_setup_wifi.sh

# Command line mode
./02_setup_wifi.sh "MySSID" "MyPassword"
```

### 3. `03_setup_cyclonedds.sh` - CycloneDDS Config
Update konfigurasi CycloneDDS untuk wireless operation.

**Fitur:**
- Auto-detect WiFi interface
- Generate KRIA config (cyclonedds.xml)
- Generate Laptop config (cyclonedds_laptop.xml)
- Create setup script (setup_dds_wifi.sh)
- Bypass CloudflareWARP/Tailscale

**Modes:**
1. WiFi only - untuk robot wireless
2. Ethernet only - untuk development
3. Both - untuk redundancy

### 4. `04_test_ros2.sh` - Test ROS2 Communication
Verify ROS2 bisa komunikasi via WiFi.

**Tests:**
- ROS2 daemon status
- Topic discovery
- Node discovery
- Service discovery
- Local pub/sub test
- Optional bandwidth test

---

## Troubleshooting

### Problem: Dongle tidak terdeteksi (lsusb tidak ada)
```bash
# Check USB power
dmesg | grep -i usb
# Try different USB port
# Check if USB hub has enough power
```

### Problem: Interface tidak muncul (no wlan0)
```bash
# Load driver manual
sudo modprobe rtl8188eu
# Check dmesg for errors
dmesg | tail -30
```

### Problem: Tidak bisa connect ke WiFi
```bash
# Check NetworkManager status
systemctl status NetworkManager
# Restart NetworkManager
sudo systemctl restart NetworkManager
# Manual connect
nmcli dev wifi connect "SSID" password "PASSWORD"
```

### Problem: ROS2 tidak bisa discover laptop
1. Pastikan ROS_DOMAIN_ID sama (default: 30)
2. Pastikan laptop sudah setup cyclonedds_laptop.xml
3. Pastikan firewall tidak block (UDP ports 7400-7500)
4. Check interface binding di cyclonedds.xml

### Problem: Service tidak jalan dengan WARP
CycloneDDS config sudah bypass WARP dengan bind ke physical interface.
Jika masih masalah:
```bash
# Check interface binding
cat config/cyclonedds.xml | grep NetworkInterface
# Pastikan interface name benar (wlan0/wlxXXX)
```

---

## File Locations

```
~/kria_ros2_ws/src/lidar_spatial_filter/
├── config/
│   ├── cyclonedds.xml          # KRIA config (auto-generated)
│   └── cyclonedds_laptop.xml   # Laptop config (copy to laptop)
├── scripts/
│   └── wifi_setup/
│       ├── 01_test_dongle.sh
│       ├── 02_setup_wifi.sh
│       ├── 03_setup_cyclonedds.sh
│       └── 04_test_ros2.sh
├── setup_dds_kria.sh           # Original ethernet setup
└── setup_dds_wifi.sh           # New WiFi setup (auto-generated)
```

---

## Network Diagram

```
                    ┌──────────────────┐
                    │   WiFi Router    │
                    │  192.168.0.1     │
                    └────────┬─────────┘
                             │
           ┌─────────────────┴─────────────────┐
           │                                   │
    ┌──────┴──────┐                     ┌──────┴──────┐
    │  KRIA KR260 │                     │   Laptop    │
    │             │                     │             │
    │ TL-WN725N   │◄───── ROS2 ────────►│  wlp3s0     │
    │ wlan0       │    CycloneDDS       │             │
    │ 192.168.0.100                     │ 192.168.0.104
    │             │                     │             │
    │ CloudflareWARP (bypassed)         │ CloudflareWARP
    │ 172.16.0.2  │                     │ (bypassed)  │
    └─────────────┘                     └─────────────┘
```

---

## Recommended Settings

### Static IP Assignments:
- KRIA Robot: 192.168.0.100
- Laptop: 192.168.0.104
- Router: 192.168.0.1

### ROS2 Environment:
```bash
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export ROS_DOMAIN_ID=30
export ROS_LOCALHOST_ONLY=0
export CYCLONEDDS_URI="file:///path/to/cyclonedds.xml"
```

### TL-WN725N Specs:
- Chipset: RTL8188EUS
- USB ID: 0bda:8179
- Speed: 150Mbps (2.4GHz)
- Linux Driver: rtl8188eu (built-in)
- Range: ~15-25m indoor
