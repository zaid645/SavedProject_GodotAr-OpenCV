# IMPLEMENTATION_EXPORT — Export Proyek ke Android (bag. 1)

Cakupan: mengekspor **proyek Godot 3.x + GDNative OpenCV** ini ke HP Android.
Fokus: template export, preset, dan skenario kamera. Build `.so` Android
membutuhkan NDK + kompilasi silang (lihat bag. 2).

> Status jujur: repo ini **teruji di Linux desktop**. Jalur Android di bawah
> adalah arahan standar Godot 3 + GDNative; bagian yang belum teruji di
> perangkat ditandai JELAS agar tidak dikira sudah beres.

---

## 1. Prasyarat (install sekali)

1. **Godot 3.6.3 + export templates Android** versi SAMA persis:
   **Editor → Manage Export Templates → Download/Install**
   (file `.tpz`), atau taruh manual di `~/.local/share/godot/templates/`.
2. **JDK 8/11** + **Android SDK** (platform android-29+) + **build-tools**.
3. Di editor: **Editor → Editor Settings → Export → Android**:
   isi `Android Sdk Path`, `Debug Keystore` (buat via `keytool -genkey`
   bila belum ada; untuk rilis pakai keystore sendiri, JANGAN debug).
4. HP Android: aktifkan **Developer Options → USB debugging**,
   colok USB, izinkan RSA fingerprint. Cek via `adb devices`.
5. Izin kamera: proyek ini butuh `CAMERA`. Di Godot 3 preset Android,
   centang **`Camera`** pada permissions (lihat §3). Tanpa ini aplikasi
   langsung gagal buka kamera di HP.

---

## 2. Buat export preset Android (manual di editor)

1. **Project → Export → Add → Android**.
2. Tab **Options** (nilai awal yang disarankan):
   - `Package / Unique Name`: mis. `org.kamu.arucoar` (wajib unik).
   - `Version Code / Version Name`: mis. `1` / `1.0`.
   - `Orientation`: `Landscape` (AR marker lebih nyaman landscape).
   - `Min Sdk / Target Sdk`: `21` / `29` (sesuaikan SDK terinstal).
   - `Permissions → Camera`: **ON**.
   - `Architectures`: centang `arm64-v8a` (HP modern); `armeabi-v7a`
     opsional bila target HP lama.
3. Tab **Resources**: pastikan `demo/bin/gd_opencv.gdns`,
   `demo/bin/gd_opencv.gdnlib`, dan library Android (bag. 2, bila sudah
   dibuild) ikut ter-export. Filter default biasanya cukup.
4. **Save** → file `export_presets.cfg` muncul di folder demo (ikut commit).

---

## 3. Export & install APK (jalur cepat — tanpa rebuild C++ dulu)

> Hasilnya: APK ter-install, TAPI library GDNative di dalamnya masih versi
> Linux `.so` sehingga **AR belum jalan di HP**. Berguna untuk cek UI/scene
> dan alur izin kamera sebelum masuk kompilasi silang.

1. **Project → Export → Android → Export Project** → `ar-debug.apk`.
2. Install: `adb install -r ar-debug.apk`, atau klik **Run on Android Device**
   (ikon HP) langsung dari editor.
3. Di HP: izinkan akses kamera saat diminta. Harapan tahap ini:
   aplikasi terbuka, UI tampil; log via `adb logcat | grep -i godot`
   akan menunjukkan library native gagal load — ITU NORMAL sebelum bag. 2.

(Lanjut ke bagian 2: kompilasi silang OpenCV+GDNative untuk Android,
skenario kamera Android, dan troubleshooting.)


---

## 4. Kompilasi silang GDNative + OpenCV untuk Android (bag. 2)

> Ini bagian BERAT. `demo/bin/x11/*.so` tidak bisa dipakai di HP.
> Butuh `demo/bin/android/arm64-v8a/libgdopencvexample.so` (+ entri
> `arm64-v8a` di `.gdnlib`).

1. Install **Android NDK** (r21+; samakan dgn template Godot 3),
   set `ANDROID_NDK_ROOT`, tambahkan toolchain ke `PATH`.
2. Siapkan **OpenCV Android SDK** (opencv.org → Android pack berisi
   `sdk/native/jni/` + `libs/arm64-v8a/`). Verifikasi ada modul
   `aruco` + `calib3d` di dalamnya.
3. Build `godot-cpp` untuk Android (dari folder repo):
   `scons platform=android android_arch=arm64v8 target=release -j$(nproc)`
   (cek `godot-cpp/bin/` menghasilkan `.android.*.a`).
4. Build library proyek dgn NDK compiler + include/lib OpenCV Android
   (sesuaikan `SConstruct` atau invoke manual; pola flag mengikuti build
   Linux tapi `--sysroot` NDK + `-DANDROID`). Output wajib:
   `demo/bin/android/arm64-v8a/libgdopencvexample.so`.
5. Tambahkan entri di `demo/bin/gd_opencv.gdnlib` (manual di teks):
   `[entry] Android.arm64-v8a="res://bin/android/arm64-v8a/libgdopencvexample.so"`.
6. Ulangi export → APK kini memuat library asli. Cek logcat:
   `[AR] OpenCVProcessing berhasil dibuat.` = sukses.

Catatan: langkah di atas sensitif versi NDK/Godot — pin versi yang sama di
semua perangkat tim dan catat di repo bila berhasil.

---

## 5. Skenario kamera di Android (pilih satu)

| Skenario | Cara | Kapan dipakai |
|---|---|---|
| A. Tetap `cv::VideoCapture` (usaha terkecil) | Kode C++ sekarang tanpa ubah; Android OpenCV membuka kamera via backend bawaan | Coba dulu; bila frame kosong di HP, lanjut B |
| B. Kamera Godot → `Image` → fungsi proses baru | Frame diteruskan ke fungsi proses baru (perlu ubah C++: tambah `process_bytes`) | Bila A gagal di HP target |
| C. Plugin kamera Android (CameraX) | Plugin terpisah menulis frame ke `AR` | Bila butuh kontrol fokus/flash penuh |

Rekomendasi: mulai A (nol ubah kode). Pindah ke B hanya bila terbukti gagal
di HP target.

---

## 6. Checklist rilis & troubleshooting

- [ ] `export_presets.cfg` ter-commit; `.apk` JANGAN di-commit.
- [ ] Ikon (`icon.png`), nama paket unik, version code naik tiap rilis.
- [ ] Uji di minimal 2 HP (beda vendor kamera) + marker layar & cetak.
- [ ] `adb logcat`: tidak ada `UnsatisfiedLinkError` / `dlopen failed`.

| Gejala di HP | Penyebab umum | Perbaikan |
|---|---|---|
| Force-close saat buka | Library `.so` Android belum ada / ABI salah | Ulangi bagian 4, cek `adb logcat` baris `dlopen` |
| UI tampil, video hitam | Izin kamera ditolak / skenario A gagal | Izinkan manual di Settings; coba skenario B |
| Marker tak terdeteksi di HP | Fokus hunting / resolusi beda | Samakan `width/height` worker dgn frame HP; perbesar marker |
| APK raksasa (>150 MB) | OpenCV full + 2 ABI | Hanya `arm64-v8a`; pertimbangkan OpenCV minimal |
