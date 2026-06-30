# Setup Laptop untuk Komunikasi ROS2 dengan KRIA Robot
**Panduan Step-by-Step Manual**

---

## 📋 PRASYARAT

Pastikan laptop Anda sudah terinstall:
- ✅ ROS2 Humble (atau Foxy/Galactic)
- ✅ Terhubung ke WiFi yang SAMA dengan KRIA (SSID: OKOKOK)

Cek dengan command:
```bash
ros2 --version
```

---

## 🔧 LANGKAH SETUP

### **STEP 1: Copy File Config dari KRIA ke Laptop**

Buka terminal di laptop, lalu jalankan SALAH SATU command berikut:

**Opsi A - Via WiFi (lebih cepat):**
```bash
scp ubuntu@192.168.0.100:~/kria_ros2_ws/src/lidar_spatial_filter/config/cyclonedds_laptop.xml ~/
```

**Opsi B - Via Tailscale (lebih stabil):**
```bash
scp ubuntu@100.76.130.74:~/kria_ros2_ws/src/lidar_spatial_filter/config/cyclonedds_laptop.xml ~/
```

> **Password:** masukkan password ubuntu KRIA Anda

Setelah berhasil, file akan tersimpan di: `~/cyclonedds_laptop.xml`

**Verifikasi file sudah ada:**
```bash
ls -lh ~/cyclonedds_laptop.xml
```

---

### **STEP 2: Cek Nama Interface WiFi Laptop**

Jalankan command ini untuk melihat nama interface WiFi laptop:
```bash
ip a | grep -E "wl|wlan"
```

**Contoh output:**
```
3: wlp3s0: <BROADCAST,MULTICAST,UP,LOWER_UP> ...
```

Nama interface di atas adalah: **wlp3s0**

> **Catatan:** Nama bisa berbeda di laptop Anda, misalnya:
> - `wlp3s0` (umum di laptop modern)
> - `wlan0` (umum di laptop lama)
> - `wlxXXXXXX` (USB WiFi dongle)

**Catat nama interface ini!** Anda akan menggunakannya di step selanjutnya.

---

### **STEP 3: Edit File Config (Jika Interface Berbeda)**

Jika nama interface WiFi laptop Anda **BUKAN** `wlp3s0`, edit file config:

```bash
nano ~/cyclonedds_laptop.xml
```

Cari baris ini:
```xml
<NetworkInterface name="wlp3s0" priority="default" multicast="true" />
```

Ganti `wlp3s0` dengan nama interface WiFi laptop Anda (dari STEP 2).

**Simpan file:**
- Tekan `Ctrl + O` (save)
- Tekan `Enter` (confirm)
- Tekan `Ctrl + X` (exit)

> **Jika interface sudah `wlp3s0`, SKIP step ini!**

---

### **STEP 4: Install CycloneDDS (Jika Belum Ada)**

Cek apakah CycloneDDS sudah terinstall:
```bash
dpkg -l | grep rmw-cyclonedds-cpp
```

**Jika TIDAK ADA output**, install dengan:
```bash
sudo apt update
sudo apt install -y ros-humble-rmw-cyclonedds-cpp
```

> Ganti `humble` dengan `foxy` atau `galactic` sesuai versi ROS2 Anda

---

### **STEP 5: Buat Script Setup Environment**

Buat file setup otomatis agar tidak perlu ketik ulang setiap kali:

```bash
nano ~/setup_ros2_kria.sh
```

Copy-paste isi berikut:

```bash
#!/bin/bash
# ROS2 Environment Setup for KRIA Robot Communication

# Source ROS2
source /opt/ros/humble/setup.bash

# Setup CycloneDDS
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export CYCLONEDDS_URI=file://$HOME/cyclonedds_laptop.xml
export ROS_DOMAIN_ID=30
export ROS_LOCALHOST_ONLY=0

# Display status
echo "╔════════════════════════════════════════════════════╗"
echo "║  ROS2 Ready - KRIA Robot Communication            ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""
echo "  RMW_IMPLEMENTATION = $RMW_IMPLEMENTATION"
echo "  ROS_DOMAIN_ID      = $ROS_DOMAIN_ID"
echo "  KRIA Robot IP      = 192.168.0.100"
echo ""
echo "Ready to communicate with KRIA!"
```

**Simpan file:**
- Tekan `Ctrl + O`, `Enter`, `Ctrl + X`

**Buat file executable:**
```bash
chmod +x ~/setup_ros2_kria.sh
```

---

## ✅ VERIFIKASI SETUP

### **Test 1: Setup Environment**

Setiap kali buka terminal baru, WAJIB jalankan:
```bash
source ~/setup_ros2_kria.sh
```

Anda akan melihat output:
```
╔════════════════════════════════════════════════════╗
║  ROS2 Ready - KRIA Robot Communication            ║
╚════════════════════════════════════════════════════╝

  RMW_IMPLEMENTATION = rmw_cyclonedds_cpp
  ROS_DOMAIN_ID      = 30
  KRIA Robot IP      = 192.168.0.100

Ready to communicate with KRIA!
```

### **Test 2: Cek Environment Variables**

```bash
echo $RMW_IMPLEMENTATION
echo $ROS_DOMAIN_ID
echo $CYCLONEDDS_URI
```

**Output yang BENAR:**
```
rmw_cyclonedds_cpp
30
file:///home/YOUR_USERNAME/cyclonedds_laptop.xml
```

---

## 🎯 CARA PAKAI SETELAH SETUP

### **SETIAP kali buka terminal:**

1. **Source environment:**
   ```bash
   source ~/setup_ros2_kria.sh
   ```

2. **Lihat topics dari KRIA:**
   ```bash
   ros2 topic list
   ```

3. **Subscribe topic dari KRIA:**
   ```bash
   ros2 topic echo /nama_topic
   ```

4. **Publish topic ke KRIA:**
   ```bash
   ros2 topic pub /test std_msgs/String "data: 'Hello KRIA'"
   ```

---

## 🆘 TROUBLESHOOTING

### **Problem: `ros2: command not found`**
**Solusi:**
```bash
source /opt/ros/humble/setup.bash
```

### **Problem: Tidak bisa copy file dari KRIA**
**Solusi:**
1. Pastikan laptop dan KRIA di network yang sama
2. Test koneksi: `ping 192.168.0.100`
3. Coba via Tailscale: `ping 100.76.130.74`

### **Problem: `ros2 topic list` tidak tampil topics dari KRIA**
**Solusi:**
1. Pastikan sudah `source ~/setup_ros2_kria.sh`
2. Cek KRIA juga sudah running ROS2 nodes
3. Verifikasi ROS_DOMAIN_ID sama (30)

---

## 📝 RINGKASAN FILE

Setelah setup selesai, Anda akan punya:

| File | Lokasi | Fungsi |
|------|--------|--------|
| `cyclonedds_laptop.xml` | `~/` | Config CycloneDDS |
| `setup_ros2_kria.sh` | `~/` | Script setup environment |

**INGAT:** Setiap terminal baru wajib: `source ~/setup_ros2_kria.sh`

---

## ✅ CHECKLIST SETUP

- [ ] File `cyclonedds_laptop.xml` sudah di-copy ke `~/`
- [ ] Interface WiFi sudah dicek dan disesuaikan di config
- [ ] CycloneDDS sudah terinstall
- [ ] File `setup_ros2_kria.sh` sudah dibuat
- [ ] Test `source ~/setup_ros2_kria.sh` berhasil
- [ ] Environment variables sudah benar (`echo $RMW_IMPLEMENTATION`)

**Jika semua ✅, setup SELESAI!**

