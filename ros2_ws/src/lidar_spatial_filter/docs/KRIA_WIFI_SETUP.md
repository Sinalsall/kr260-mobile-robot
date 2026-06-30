# 🤖 WiFi Setup Guide - KRIA KR260 Robot
## TP-Link TL-WN725N + ROS2 Humble + CycloneDDS

---

## 📋 Prerequisites

- [x] KRIA KR260 dengan Ubuntu 22.04
- [x] ROS2 Humble terinstall
- [x] CycloneDDS terinstall (`sudo apt install ros-humble-rmw-cyclonedds-cpp`)
- [x] WiFi Dongle: TP-Link TL-WN725N (atau compatible RTL8188EUS)
- [x] Akses ke WiFi network yang sama dengan laptop

---

## 🚀 Quick Start (5 Menit)

```bash
# 1. Colok WiFi dongle ke USB port KRIA

# 2. Masuk ke direktori setup
cd ~/kria_ros2_ws/src/lidar_spatial_filter/scripts/wifi_setup

# 3. Test dongle (pastikan terdeteksi)
./01_test_dongle.sh

# 4. Setup WiFi connection
./02_setup_wifi.sh

# 5. Setup CycloneDDS untuk WiFi
./03_setup_cyclonedds.sh

# 6. Test ROS2
./04_test_ros2.sh

# 7. Copy config ke laptop (lihat section "Transfer ke Laptop")
```

---

## 📖 Detailed Steps

### Step 1: Colok WiFi Dongle

Colok TL-WN725N ke salah satu USB port KRIA KR260.

**USB Ports yang tersedia:**
- USB 3.0 ports (biru) - recommended
- USB 2.0 ports - juga bisa

### Step 2: Test Dongle Compatibility

```bash
cd ~/kria_ros2_ws/src/lidar_spatial_filter/scripts/wifi_setup
./01_test_dongle.sh
```

**Expected Output:**
```
[✓ PASS] TL-WN725N (RTL8188EUS) terdeteksi!
  Chipset: RTL8188EUS
  USB ID:  0bda:8179

[✓ PASS] Driver rtl8188eu loaded
[✓ PASS] Wireless interface ditemukan: wlan0
[✓ PASS] Dapat scan WiFi networks: 5 networks ditemukan

DONGLE COMPATIBLE! Ready for setup.
```

**Jika FAIL:**
```bash
# Troubleshooting
dmesg | tail -30                    # Check kernel messages
sudo modprobe rtl8188eu             # Load driver manual
lsusb                               # Check USB detection
```

### Step 3: Setup WiFi Connection

```bash
./02_setup_wifi.sh
```

**Interactive mode akan:**
1. Scan available WiFi networks
2. Minta SSID dan password
3. Set static IP (default: 192.168.0.100)
4. Enable auto-connect on boot
5. Test connectivity

**Atau dengan command line:**
```bash
./02_setup_wifi.sh "NamaWiFi" "PasswordWiFi"
```

**Verifikasi koneksi:**
```bash
# Check IP address
ip addr show wlan0

# Test ping ke router
ping -c 3 192.168.0.1

# Test ping ke laptop (jika sudah konek)
ping -c 3 192.168.0.104
```

### Step 4: Setup CycloneDDS

```bash
./03_setup_cyclonedds.sh
```

**Script akan:**
1. Detect WiFi interface otomatis
2. Generate `cyclonedds.xml` untuk KRIA
3. Generate `cyclonedds_laptop.xml` untuk laptop
4. Create `setup_dds_wifi.sh` script
5. Backup config lama

**Dengan laptop IP langsung:**
```bash
./03_setup_cyclonedds.sh 192.168.0.104
```

### Step 5: Test ROS2 Communication

```bash
./04_test_ros2.sh
```

**Test local pub/sub:**
```bash
# Terminal 1 - Subscribe
source ~/kria_ros2_ws/src/lidar_spatial_filter/setup_dds_wifi.sh
ros2 topic echo /test

# Terminal 2 - Publish
source ~/kria_ros2_ws/src/lidar_spatial_filter/setup_dds_wifi.sh
ros2 topic pub /test std_msgs/msg/String "data: 'hello'"
```

---

## 📤 Transfer Config ke Laptop

### Metode A: SCP (Recommended)

```bash
# Dari KRIA, kirim ke laptop
scp ~/kria_ros2_ws/src/lidar_spatial_filter/config/cyclonedds_laptop.xml \
    YOUR_USERNAME@192.168.0.104:~/

# Contoh:
scp ~/kria_ros2_ws/src/lidar_spatial_filter/config/cyclonedds_laptop.xml \
    sinalsal@192.168.0.104:~/
```

### Metode B: Copy-Paste Manual

```bash
# Di KRIA, tampilkan isi file
cat ~/kria_ros2_ws/src/lidar_spatial_filter/config/cyclonedds_laptop.xml

# Copy output, lalu di laptop:
nano ~/cyclonedds_laptop.xml
# Paste dan save
```

### Metode C: USB Drive

```bash
# Di KRIA
cp ~/kria_ros2_ws/src/lidar_spatial_filter/config/cyclonedds_laptop.xml /media/usb/

# Di Laptop
cp /media/usb/cyclonedds_laptop.xml ~/
```

---

## ⚡ Penggunaan Sehari-hari

### Setiap Kali Boot KRIA:

```bash
# WiFi akan auto-connect (sudah di-setup)

# Source environment sebelum ROS2
source ~/kria_ros2_ws/src/lidar_spatial_filter/setup_dds_wifi.sh

# Atau tambahkan ke ~/.bashrc:
echo 'source ~/kria_ros2_ws/src/lidar_spatial_filter/setup_dds_wifi.sh' >> ~/.bashrc
```

### Launch Robot Nodes:

```bash
# Source workspace
source ~/kria_ros2_ws/install/setup.bash

# Source DDS config
source ~/kria_ros2_ws/src/lidar_spatial_filter/setup_dds_wifi.sh

# Launch your nodes
ros2 launch your_package robot.launch.py
```

---

## 🔧 Switch Between WiFi dan Ethernet

### Pakai WiFi:
```bash
source ~/kria_ros2_ws/src/lidar_spatial_filter/setup_dds_wifi.sh
```

### Pakai Ethernet (eth1):
```bash
source ~/kria_ros2_ws/src/lidar_spatial_filter/setup_dds_kria.sh
```

---

## 🐛 Troubleshooting

### WiFi Disconnect

```bash
# Reconnect manual
nmcli con up kria-robot-wifi

# Check status
nmcli con show kria-robot-wifi

# Restart NetworkManager
sudo systemctl restart NetworkManager
```

### ROS2 Tidak Discover Laptop

```bash
# 1. Check environment
echo $CYCLONEDDS_URI
echo $RMW_IMPLEMENTATION
echo $ROS_DOMAIN_ID

# 2. Restart ROS2 daemon
ros2 daemon stop
ros2 daemon start

# 3. Check network
ping 192.168.0.104    # Laptop IP

# 4. Check firewall
sudo ufw status
sudo ufw allow 7400:7500/udp    # DDS ports
```

### Service Tidak Jalan

```bash
# Pastikan interface binding benar
cat ~/kria_ros2_ws/src/lidar_spatial_filter/config/cyclonedds.xml | grep NetworkInterface

# Harus menunjukkan wlan0, BUKAN eth1 atau CloudflareWARP
```

---

## 📁 File Locations

```
~/kria_ros2_ws/src/lidar_spatial_filter/
├── config/
│   ├── cyclonedds.xml          # ← Config untuk KRIA (WiFi)
│   ├── cyclonedds_laptop.xml   # ← Config untuk Laptop (copy ini!)
│   └── cyclonedds.xml.backup_* # ← Backup config lama
├── scripts/
│   └── wifi_setup/
│       ├── 01_test_dongle.sh
│       ├── 02_setup_wifi.sh
│       ├── 03_setup_cyclonedds.sh
│       ├── 04_test_ros2.sh
│       └── README.md
├── setup_dds_kria.sh           # ← Setup untuk Ethernet
└── setup_dds_wifi.sh           # ← Setup untuk WiFi ⭐
```

---

## 📊 Network Settings

| Device | Interface | IP Address | Role |
|--------|-----------|------------|------|
| KRIA | wlan0 | 192.168.0.100 | Robot |
| KRIA | eth1 | 192.168.0.100 | Backup |
| Laptop | wlp3s0 | 192.168.0.104 | Ground Station |
| Router | - | 192.168.0.1 | Gateway |

| Setting | Value |
|---------|-------|
| ROS_DOMAIN_ID | 30 |
| RMW_IMPLEMENTATION | rmw_cyclonedds_cpp |
| Multicast | SPDP only |
| Discovery | Unicast peers |

---

## ✅ Checklist

- [ ] WiFi dongle terdeteksi (`lsusb`)
- [ ] Interface wlan0 muncul (`ip link show`)
- [ ] WiFi connected (`nmcli con show`)
- [ ] Got IP 192.168.0.100 (`ip addr show wlan0`)
- [ ] Dapat ping laptop (`ping 192.168.0.104`)
- [ ] cyclonedds.xml updated untuk wlan0
- [ ] cyclonedds_laptop.xml sudah di-copy ke laptop
- [ ] `ros2 topic list` dari laptop bisa lihat topics KRIA
- [ ] `ros2 service list` dari laptop bisa lihat services KRIA
