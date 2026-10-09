# Scene Implementation — Panduan Manual (Godot 3.6.3)

> File `.gd` sudah jadi (hasil Act). File `.tscn` SENGAJA tidak dibuatkan
> otomatis — buat manual di editor mengikuti langkah di bawah.
> Berlaku untuk Godot 3.x (repo ini GDNative `.gdns`, teruji pola Godot 3.5/3.6).

File kode yang sudah tersedia:
- `demo/Main2D.gd` — debug video 2D (reuse texture, paksa `show_processed`, status).
- `demo/MainAR.gd` — AR 3D pose PENUH (posisi + kemiringan via konversi rvec→Basis)
  + multi-model per ID (spawn otomatis dari `Cube` / `model_scenes`).
- C++ TIDAK diubah pada tahap ini (rvec yang sudah ada cukup).

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

## C2. Perbaikan wajib untuk Main3D buatanmu (hasil konfirmasi)

Dua hal yang ditemukan saat konfirmasi `Main3D.tscn` milikmu:

1. **Pindahkan `StatusLabel` jadi child `Main3D` (root).**
   Saat ini ia child dari `ARWorker`, sedangkan `MainAR.gd` mencari
   `$StatusLabel` di root — akibatnya label tak pernah update
   (jatuh ke `print()`, tidak crash). Cara: di SceneTree drag
   `StatusLabel` keluar dari `ARWorker` ke `Main3D`, atur ulang
   posisi Label (anchor/offset) karena koordinatnya ikut berubah.
2. **Biarkan `Cube` tetap ada sebagai TEMPLATE** (jangan dihapus).
   Kode baru men-duplikatnya per ID marker + memberi warna unik per ID.
   `Cube` sendiri selalu disembunyikan di `_ready()`.

## C3. Uji kemiringan / tilt (bagian A — tanpa ubah C++)

Tidak ada langkah scene tambahan. Setelah `.gd` baru tersimpan:

1. Run `Main3D`, arahkan 1 marker.
2. Miringkan HP/kertas perlahan → model ikut miring (rotasi penuh dari rvec).
3. Baca `StatusLabel`: format baru `ID [7] | miring 23°`.
   `0°` = tegak menghadap kamera; angka naik saat dimiringkan.
   Ini bukti kanal `rotations` sudah dipakai (sebelumnya diabaikan).

## C4. Multi-model per ID (bagian B — tanpa tambah node manual)

Tidak ada node yang perlu ditambah manual — kode men-spawn sendiri:

1. **Tanpa `.glb` (langsung bisa dicoba):** tampilkan 2–3 marker ID berbeda
   (mis. 7 dan 12) bersamaan → tiap ID dapat kubus sendiri berwarna unik
   (fallback duplikat `Cube`). Marker yang keluar frame → kubusnya hilang,
   yang lain tetap tampil.
2. **Dengan `.glb` (opsional, bila sudah punya model):**
   a. Taruh file mis. `demo/models/kursi.glb`, `demo/models/mobil.glb`.
   b. Di editor: Scene → New Scene → pilih root `Spatial` → tambah child
      `MeshInstance` → load GLB-nya → **Scene → Save Branch as Scene**
      menjadi mis. `demo/models/Kursi.tscn`.
   c. Pilih root `Main3D` → Inspector → property `model_scenes`
      (Dictionary) → tambah entri: key `7` → value load `Kursi.tscn`,
      key `12` → `Mobil.tscn`.
   d. Run → ID 7 memunculkan kursi, ID 12 memunculkan mobil.
3. **Filter ID (opsional):** Inspector → `target_id`: `-1` = semua marker,
   mis. `7` = hanya ID 7 yang ditampilkan.
4. **Kehalusan:** `smooth_factor` 8.0 default; kecilkan bila lag,
   besarkan bila jitter.

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
| E5 | Run `Main3D` + arahkan marker | Model muncul + ikut miring, status `ID [7] \| miring N°` | Cek koneksi sinyal C.7 + `ARWorker` visible off tapi **enabled**, `marker_length` 0.05; bila tak miring, `.gd` belum tersimpan/ter-reload |
| E5b | 2+ marker ID beda bersamaan | Tiap ID kubus sendiri warna unik; yang hilang → kubusnya hilang | Bila semua kubus sama: normal sebelum `.glb` diisi (fallback). Bila hanya 1 tampil: cek `target_id` = -1 |
| E6 | Gerak halus | Tidak bergetar liar (`smooth_factor` 8.0, slerp rotasi) | Wajar goyang sebelum kalibrasi. Kecilkan `smooth_factor` bila lag, besarkan bila jitter |

Tips marker-dari-layar: kunci brightness maksimal, matikan True-Tone/Night-Light,
perbesar marker hingga ~1/4 tinggi layar, hindari pantulan lampu (miringkan HP
5–10°), dan dekatkan perlahan dari ~50 cm ke ~25 cm sampai terdeteksi.

## F. Batasan Tahap Ini (jujur)

- `camera_matrix` masih perkiraan `fx=0.9*width` — pose bisa goyang; kalibrasi
  papan catur belakangan.
- Deteksi jalan tiap frame (CPU). Bila berat, optimasi interval/thread menyusul.
- Multi-model `.glb`: skrip menerima PackedScene apa pun, tapi model sangat
  besar belum diuji — mulai dari `.glb` kecil dulu.
- Batasan multi-marker menjawab pertanyaanmu: deteksi TIDAK dibatasi 1 marker
  (semua ID dikirim C++); yang tampil hanya yang lolos `target_id` + punya node.
