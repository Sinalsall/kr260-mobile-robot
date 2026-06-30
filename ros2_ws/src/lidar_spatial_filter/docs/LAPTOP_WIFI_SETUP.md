# 💻 WiFi Setup Guide - Laptop (Ground Station)
## Komunikasi dengan KRIA KR260 Robot via ROS2 + CycloneDDS

---

## 📋 Prerequisites

- [x] Ubuntu 20.04/22.04 dengan ROS2 Humble
- [x] CycloneDDS terinstall
- [x] Terhubung ke WiFi yang sama dengan robot KRIA
- [x] File `cyclonedds_laptop.xml` dari KRIA

---

## 🚀 Quick Start (2 Menit)

```bash
# 1. Pastikan sudah dapat file cyclonedds_laptop.xml dari KRIA
ls ~/cyclonedds_laptop.xml

# 2. Cek nama interface WiFi laptop
ip link show | grep wl

# 3. Edit interface name jika perlu
nano ~/cyclonedds_laptop.xml
# Ubah "wlp3s0" ke nama interface WiFi Anda

# 4. Setup environment
export CYCLONEDDS_URI=file://$HOME/cyclonedds_laptop.xml
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export ROS_DOMAIN_ID=30

# 5. Test komunikasi
ros2 topic list
ros2 node list
```

---

## 📖 Detailed Steps

### Step 1: Dapatkan Config File dari KRIA

File `cyclonedds_laptop.xml` di-generate oleh KRIA. 

**Cara mendapatkan:**

```bash
# Metode A: SCP dari KRIA
scp ubuntu@192.168.0.100:~/kria_ros2_ws/src/lidar_spatial_filter/config/cyclonedds_laptop.xml ~/

# Metode B: SCP ke laptop (dari KRIA)
# Di KRIA jalankan:
# scp config/cyclonedds_laptop.xml YOUR_USER@192.168.0.104:~/

# Metode C: Copy-paste manual
# Di KRIA: cat config/cyclonedds_laptop.xml
# Copy output, di laptop: nano ~/cyclonedds_laptop.xml dan paste
```

### Step 2: Identifikasi Interface WiFi Laptop

```bash
# Lihat semua network interfaces
ip link show

# Atau khusus wireless
ip link show | grep wl
iw dev

# Contoh output:
# 3: wlp3s0: <BROADCAST,MULTICAST,UP,LOWER_UP>
# Nama interface = wlp3s0
```

**Nama interface WiFi umum:**
- `wlp3s0` - Laptop dengan PCI WiFi
- `wlan0` - Generic naming
- `wlxXXXXXXXXXXXX` - USB WiFi adapter

### Step 3: Edit Config File (Jika Perlu)

```bash
nano ~/cyclonedds_laptop.xml
```

**Cari baris ini:**
```xml
<NetworkInterface name="wlp3s0" priority="default" multicast="true" />
```

**Ubah `wlp3s0` ke nama interface WiFi laptop Anda.**

**Contoh jika interface Anda `wlan0`:**
```xml
<NetworkInterface name="wlan0" priority="default" multicast="true" />
```

### Step 4: Setup Environment Variables

**Temporary (untuk session ini saja):**
```bash
export CYCLONEDDS_URI=file://$HOME/cyclonedds_laptop.xml
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export ROS_DOMAIN_ID=30
export ROS_LOCALHOST_ONLY=0
```

**Permanent (tambahkan ke ~/.bashrc):**
```bash
# Tambahkan di akhir ~/.bashrc
cat >> ~/.bashrc << 'EOF'

# === CycloneDDS config for KRIA Robot Communication ===
export CYCLONEDDS_URI=file://$HOME/cyclonedds_laptop.xml
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export ROS_DOMAIN_ID=30
export ROS_LOCALHOST_ONLY=0
EOF

# Apply changes
source ~/.bashrc
```

### Step 5: Test Komunikasi dengan KRIA

```bash
# Pastikan KRIA sudah menjalankan ROS2 nodes

# Test topic discovery
ros2 topic list

# Test node discovery
ros2 node list

# Test service discovery
ros2 service list

# Echo topic dari robot
ros2 topic echo /scan    # atau topic lain dari robot
```

---

## 📝 Setup Script untuk Laptop

Buat script untuk memudahkan setup:

```bash
# Buat script
cat > ~/setup_ros2_kria.sh << 'EOF'
#!/bin/bash
# Setup ROS2 komunikasi dengan KRIA Robot

# Source ROS2
source /opt/ros/humble/setup.bash

# Source workspace (jika ada)
if [ -f ~/ros2_ws/install/setup.bash ]; then
    source ~/ros2_ws/install/setup.bash
fi

# CycloneDDS config untuk KRIA
export CYCLONEDDS_URI=file://$HOME/cyclonedds_laptop.xml
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export ROS_DOMAIN_ID=30
export ROS_LOCALHOST_ONLY=0

echo "[ROS2 KRIA Setup]"
echo "  CYCLONEDDS_URI     = $CYCLONEDDS_URI"
echo "  RMW_IMPLEMENTATION = $RMW_IMPLEMENTATION"
echo "  ROS_DOMAIN_ID      = $ROS_DOMAIN_ID"
echo ""
echo "Ready to communicate with KRIA robot!"
EOF

# Make executable
chmod +x ~/setup_ros2_kria.sh

# Usage
source ~/setup_ros2_kria.sh
```

---

## ⚡ Penggunaan Sehari-hari

### Setiap Buka Terminal Baru:

```bash
source ~/setup_ros2_kria.sh
```

### Atau Otomatis (di ~/.bashrc):

```bash
echo 'source ~/setup_ros2_kria.sh' >> ~/.bashrc
```

### Monitor Robot:

```bash
# Lihat semua topics
ros2 topic list

# Monitor sensor data
ros2 topic echo /scan
ros2 topic echo /odom
ros2 topic echo /camera/image_raw

# Lihat TF tree
ros2 run tf2_tools view_frames

# RViz
rviz2
```

### Kirim Command ke Robot:

```bash
# Publish velocity command
ros2 topic pub /cmd_vel geometry_msgs/msg/Twist "{linear: {x: 0.1}, angular: {z: 0.0}}"

# Call service
ros2 service call /your_service std_srvs/srv/Empty
```

---

## 🐛 Troubleshooting

### Problem: Tidak bisa lihat topics dari KRIA

```bash
# 1. Check apakah KRIA bisa di-ping
ping 192.168.0.100

# 2. Check environment
echo $ROS_DOMAIN_ID          # Harus 30
echo $RMW_IMPLEMENTATION     # Harus rmw_cyclonedds_cpp
echo $CYCLONEDDS_URI         # Harus file://...

# 3. Check interface binding di config
cat ~/cyclonedds_laptop.xml | grep NetworkInterface
# Pastikan nama interface benar

# 4. Restart ROS2 daemon
ros2 daemon stop
ros2 daemon start

# 5. Check firewall
sudo ufw status
sudo ufw allow 7400:7500/udp
```

### Problem: Service tidak responsive

```bash
# 1. Check service list
ros2 service list

# 2. Pastikan tidak pakai VPN yang interfere
# CycloneDDS harus bind ke physical WiFi interface, bukan VPN

# 3. Check jika CloudflareWARP aktif
ip addr show | grep -E "CloudflareWARP|tailscale"
# Jika ada, pastikan cyclonedds.xml bind ke wlp3s0, bukan VPN interface
```

### Problem: Latency tinggi

```bash
# Test latency
ping 192.168.0.100

# Jika >50ms, mungkin:
# - WiFi signal lemah
# - Interference dari device lain
# - Router congested

# Test bandwidth
# Di KRIA: iperf3 -s
# Di Laptop: iperf3 -c 192.168.0.100
```

### Problem: Topics intermittent (kadang muncul kadang tidak)

```bash
# Increase discovery timeout di cyclonedds.xml
# Tambahkan di section <Discovery>:
#   <ParticipantIndex>auto</ParticipantIndex>
#   <MaxAutoParticipantIndex>120</MaxAutoParticipantIndex>

# Atau paksa unicast discovery dengan menambah peer
# Di <Peers> section
```

---

## 📁 File Locations

```
~/
├── cyclonedds_laptop.xml    # ← CycloneDDS config (dari KRIA)
├── setup_ros2_kria.sh       # ← Setup script (buat sendiri)
└── ros2_ws/                 # ← ROS2 workspace Anda
    └── install/
        └── setup.bash
```

---

## 📊 Network Settings (Harus Match dengan KRIA)

| Setting | Value |
|---------|-------|
| Laptop IP | 192.168.0.104 |
| KRIA IP | 192.168.0.100 |
| ROS_DOMAIN_ID | 30 |
| RMW_IMPLEMENTATION | rmw_cyclonedds_cpp |
| WiFi Interface | wlp3s0 (sesuaikan!) |

---

## 🔄 Jika IP Berubah

Jika IP KRIA berubah, update config:

```bash
nano ~/cyclonedds_laptop.xml

# Ubah baris ini:
# <Peer address="192.168.0.100"/>
# ke IP baru KRIA
```

---

## ✅ Checklist

- [ ] File `cyclonedds_laptop.xml` sudah ada di `~/`
- [ ] Interface name di config sudah benar (wlp3s0/wlan0/etc)
- [ ] Environment variables sudah di-set
- [ ] Laptop dan KRIA di WiFi network yang sama
- [ ] Dapat ping KRIA (`ping 192.168.0.100`)
- [ ] `ros2 topic list` menampilkan topics dari KRIA
- [ ] `ros2 service list` menampilkan services dari KRIA
