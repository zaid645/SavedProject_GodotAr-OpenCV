# Scene Implementation — Panduan Manual (Godot 3.6.3)

> File `.gd` sudah jadi (hasil Act). File `.tscn` SENGAJA tidak dibuatkan
> otomatis — buat manual di editor mengikuti langkah di bawah.
> Berlaku untuk Godot 3.x (repo ini GDNative `.gdns`, teruji pola Godot 3.5/3.6).

File kode yang sudah tersedia:
- `demo/Main2D.gd` — debug video 2D (reuse texture, paksa `show_processed`, status).
- `demo/MainAR.gd` — logika AR 3D (kubus CubeMesh mengikuti `marker_detected`).

---

## A. Siapkan Marker di Layar Ponsel (tanpa print fisik)

1. Di HP/laptop lain, buka generator ArUco **DICT_4X4_50** (mis. `chev.me/arucogen`
   atau script OpenCV `cv2.aruco.drawMarker(DICT_4X4_50, id)`).
2. Pilih ID bebas (mis. **7**), ukuran besar, full-brightness.
3. Tampilkan fullscreen, matikan auto-rotate & night-mode (layar kuning merusak deteksi).
4. Catatan: layar memantulkan cahaya — miringkan sedikit bila tidak terdeteksi,
   naikkan brightness, jauhi pantulan lampu.

## B. Upgrade `Main2D.tscn` (debug video) — tanpa ganti file via kode

1. Buka `demo/Main2D.tscn` di editor Godot 3.6.3.
2. Pilih node `Sprite` → Inspector → centang **`show_processed = true`**.
   (Walau `Main2D.gd:_ready()` juga memaksa `true` via kode, centang ini tetap
   disarankan agar benar sejak frame pertama.)
3. Masih di `Sprite` → Inspector → **`Visible = OFF`**
   (node ini worker kamera, yang tampil cukup `TextureRect`).
4. Tambah node `Label` sebagai child `Main2D`, rename jadi **`StatusLabel`**,
   letakkan di bawah `webcamView` (text awal bebas — akan ditimpa skrip).
5. Tab **Node → Signals**: pastikan ada 2 koneksi dari `Sprite` ke `Main2D`:
   - `frame_updated(node, image)` → `_on_Sprite_frame_updated`
   - `marker_detected(node, ids, translations, rotations)` → `_on_Sprite_marker_detected`
   Jika `marker_detected` belum muncul di daftar, **klik kanan `.gdnlib` →
   Reload / restart editor** agar sinyal baru dari `.so` terbaca, lalu hubungkan.
6. Save scene (`Ctrl+S`).

## C. Buat `Main3D.tscn` (scene AR kubus) — BARU, manual

1. **Scene → New Scene → 3D Scene.** Save sebagai `demo/Main3D.tscn`.
2. Root otomatis `Spatial` → rename jadi **`Main3D`**, attach script
   `demo/MainAR.gd` (drag file ke Inspector root).
3. Tambah child **`Camera`** (Camera3D di Godot 3: `Camera`):
   - `Transform`: posisi `(0, 0, 0)`, menghadap `-Z` (default).
   - `Projection`: Keep Aspect, FOV ~60 (perkiraan; kalibrasi presisi belakangan).
4. Tambah child **`MeshInstance`** → rename **`Cube`**:
   - `Mesh` → New `CubeMesh`, Size `(0.05, 0.05, 0.05)` (= marker 5 cm).
   - `Material` → New `SpatialMaterial`, Albedo warna terang (mis. oranye),
     aktifkan `Emission` ringan agar terlihat di ruangan gelap.
   - Awal `Visible = OFF` (skrip juga memaksa off di `_ready`).
5. Tambah child **`Sprite`** → rename **`ARWorker`**:
   - Attach NativeScript `demo/bin/gd_opencv.gdns`.
   - Inspector: `show_processed = true`, `marker_length = 0.05`,
     `Visible = OFF`.
6. Tambah child **`Label`** → rename **`StatusLabel`** (UI overlay status).
7. Koneksi sinyal: pilih `ARWorker` → tab **Node → Signals** →
   `marker_detected(node, ids, translations, rotations)` → **Connect** ke
   node `Main3D`, method `_on_ARWorker_marker_detected`.
8. (Opsional, debug ganda) tambah `TextureRect` + hubungkan `frame_updated`
   bila ingin video + kubus tampil bersamaan.
9. Save. Untuk menjalankan AR: **Project → Project Settings →
   Application → Run → Main Scene** arahkan ke `Main3D.tscn`
   (kembalikan ke `Main2D.tscn` bila ingin debug video saja).

## D. Build & Jalankan (terminal, BUKAN dari icon)

```bash
cd /home/linuxlite/000_ZFile_000/GodotProject/ArTest/godot-cpp-opencv
scons platform=linux -j$(nproc)
ls -l demo/bin/x11/libgdopencvexample.so   # pastikan timestamp baru
# Jalankan editor / game dari terminal agar LD_LIBRARY_PATH OpenCV terbawa:
godot --path demo        # Godot 3.6.3; bila binary bernama godot3, pakai itu
```

## E. Cara Mengecek (apakah dari scene yang kamu buat)

Ya — semua pengecekan dilakukan **dari scene yang kamu buat di editor + log Output**.
Urutan yang diharapkan (ikuti berurutan, berhenti di yang gagal):

| # | Cek di mana | Yang diharapkan | Artinya bila gagal |
|---|-------------|-----------------|-------------------|
| E1 | Output log saat Run `Main2D` | `[AR] OpenCVProcessing berhasil dibuat.` + `[AR] Pemrosesan aktif...` | `.so` lama / sinyal belum reload → rebuild + restart editor |
| E2 | Output log, tanpa marker di depan kamera | `Menunggu marker...` saja, tanpa spam | Normal (idle). Bila ada `PEMROSESAN NONAKTIF` → `show_processed` masih false (cek B.2) |
| E3 | Arahkan marker HP ke webcam | `[AR] MARKER TERDETEKSI! ID: 7` + kotak hijau + **sumbu XYZ** di video | Tanpa kotak: masalah marker (bukan DICT_4X4_50 / terlalu kecil / glare layar). Tanpa sumbu: pose belum jalan |
| E4 | Label `StatusLabel` di `Main2D` | Berubah jadi `Marker ID: 7` | Koneksi `marker_detected` belum dibuat (cek B.5) |
| E5 | Run `Main3D` + arahkan marker | `Cube` muncul, bergeser saat HP digeser, hilang saat marker keluar frame | Cek koneksi sinyal C.7 + `ARWorker` visible off tapi **enabled**, `marker_length` 0.05 |
| E6 | Gerak halus | Kubus tidak bergetar liar (`smooth_factor` 8.0) | Wajar goyang sebelum kalibrasi (Fase 5 plan). Kecilkan `smooth_factor` bila lag, besarkan bila jitter |

Tips marker-dari-layar: kunci brightness maksimal, matikan True-Tone/Night-Light,
perbesar marker hingga ~1/4 tinggi layar, hindari pantulan lampu (miringkan HP
5–10°), dan dekatkan perlahan dari ~50 cm ke ~25 cm sampai terdeteksi.

## F. Batasan Tahap Ini (jujur)

- Rotasi kubus belum mengikuti kemiringan kertas/HP (hanya posisi). Rotasi penuh
  butuh matriks Rodrigues dari C++ → direncanakan sebagai upgrade setelah
  posisi stabil (Fase 5 di `plan_implementation.md`).
- `camera_matrix` masih perkiraan `fx=0.9*width` — pose bisa goyang; kalibrasi
  papan catur belakangan.
- Deteksi jalan tiap frame (CPU). Bila berat, optimasi interval/thread menyusul.
