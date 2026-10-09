# Plan Implementation — AR ArUco → Objek 3D Menempel di Godot

Target: marker fisik **ArUco DICT_4X4_50** yang ditangkap webcam → **objek 3D Godot muncul & menempel mengikuti marker**.
Status saat ini (6 Okt 2026): **baru sampai akses kamera + tampil video mentah. AR belum muncul.**

File ini merangkum: (1) kondisi terkini C++ & Godot, (2) daftar kesalahan / kekurangan, (3) langkah perbaikan berfase beserta contoh potongan kode.

---

## 1. Kondisi Saat Ini

### 1.1 Alur data yang berjalan sekarang

```
Webcam → cv::VideoCapture (gd_opencv.cpp) → process_image(frame, show_processed)
  → cvMat_to_Image() → sinyal frame_updated(Image) → Main2D.gd → TextureRect.webcamView
```

Kamera berhasil karena `VideoCapture` + konversi `Mat→Image` + sinyal sudah tersambung (`Main2D.tscn` ada connection `frame_updated → _on_Sprite_frame_updated`).

### 1.2 Sisi C++ — `src/own_opencv_processing.{h,cpp}`

Yang sudah benar:

- Dictionary `DICT_4X4_50` dibuat di constructor — cocok dengan marker yang dipakai user (bukan QR, jadi tidak perlu `QRCodeDetector`).
- `detectMarkers()` + `drawDetectedMarkers()` sudah dipanggil dengan benar.
- Logging diagnostik `[AR] ...` sudah baik (aktif / nonaktif / marker hilang / ID berubah).

Yang belum / salah:

1. **Hanya overlay 2D, bukan AR 3D.** Tidak ada `estimatePoseSingleMarkers` / `solvePnP` / `drawAxis`, tidak ada `cameraMatrix` + `distCoeffs`. Tanpa pose, mustahil menempelkan objek 3D.
2. **Pose tidak dikembalikan ke Godot.** `process_image()` mengembalikan `cv::Mat` saja. `frame_updated` hanya membawa `Image`. GDScript tidak pernah tahu ID / sudut / posisi marker.
3. **`DetectorParameters::create()` tiap frame** (`own_opencv_processing.cpp:104-105`) — boros; seharusnya di-cache sebagai member.
4. State `static` (`warned_*`, `processing_started`, `previous_marker_ids`) bersifat global antar-instance — OK untuk 1 kamera, rapuh kalau node digandakan.

### 1.3 Sisi Godot — `demo/Main2D.tscn` + `demo/Main2D.gd`

`Main2D.tscn` saat ini (lengkap):

```ini
[node name="webcamView" type="TextureRect" parent="."]
margin_right = 640.0
margin_bottom = 480.0
expand = true

[node name="Sprite" type="Sprite" parent="."]
script = ExtResource( 1 )
```

`Main2D.gd` saat ini (lengkap):

```gdscript
extends Control

func _ready():
    pass

func _on_Sprite_frame_updated(node, image):
    var image_texture:ImageTexture = ImageTexture.new()
    image_texture.create_from_image(image)
    $webcamView.texture = image_texture
```

Kekurangan di sisi Godot (ini menjawab pertanyaan user — **ya, sisi Godot juga kurang**):

| # | Masalah | Lokasi | Dampak |
|---|---------|--------|--------|
| G1 | `show_processed` **tidak pernah di-set `true`** di `.tscn` maupun `.gd`. Default di C++ adalah `false` (`gd_opencv.cpp:11,48`). Akibatnya `process_image()` selalu early-return frame mentah | `Main2D.tscn:16-17`, `gd_opencv.cpp:48` | **Root cause utama**: deteksi tidak pernah jalan walau kamera jalan |
| G2 | `ImageTexture.new()` dibuat **tiap frame** di callback sinyal (~30-60x/detik) | `Main2D.gd:21` | GC pressure / bocor memori, frame drop. Harus reuse satu `ImageTexture` |
| G3 | Tidak ada consumer untuk hasil deteksi (ID / pose). Sinyal cuma `frame_updated(node, image)`, tidak ada `marker_detected` | `Main2D.gd`, `gd_opencv.cpp:14` | Godot tidak bisa menempelkan objek 3D karena tidak tahu marker di mana |
| G4 | Node `Sprite` (pembawa NativeScript) tidak pernah menyembunyikan texture-nya sendiri / tidak di-`hide()`; ia menumpuk tak terlihat di (0,0) sementara yang tampil `TextureRect` | `Main2D.tscn:16-17` | Membingungkan; peran ganda. Sebaiknya node worker di-hide atau diganti `Node` |
| G5 | Tidak ada UI status (label "menunggu marker / marker ID: X") dan tidak ada handling kamera gagal dibuka | `Main2D.gd` | Sulit debug: user tidak tahu apakah gagal di kamera, di flag, atau di marker |
| G6 | Scene masih 2D-only (`Control` + `TextureRect`). Untuk "objek 3D menempel" butuh scene 3D (`Camera` + `MeshInstance`) atau minimal proyeksi koordinat | `Main2D.tscn`, `project.godot` | Target user (objek 3D) belum punya wadah |

### 1.4 Bug nyata di `src/gd_opencv.cpp:133-141` (`cvMat_to_Image`)

```cpp
// SALAH — jangan pakai pola ini:
for (int i=0; i < sizeof(cv_rgb); i++)
{
    std::memcpy(bytes.write().ptr(), cv_rgb.ptr(i), numel);
}
```

`sizeof(cv::Mat)` = ukuran objek C++ (bukan jumlah baris), dan tiap iterasi menyalin `numel` byte ke alamat yang **sama** → overflow/korupsi saat frame non-continuous. Umumnya frame webcam continuous sehingga lolos, tapi tetap harus diperbaiki (lihat contoh di Fase 1).

---

## 2. Prioritas Perbaikan (ringkas)

1. **P0 — Nyalakan saklar:** `show_processed = true` (tscn + `_ready`) + rebuild `.so` + cek log `[AR]`.
2. **P0 — Perbaiki `cvMat_to_Image()`** cabang non-continuous.
3. **P1 — Estimasi pose + kembalikan ke Godot:** `cameraMatrix/distCoeffs` + `estimatePoseSingleMarkers` + sinyal/GDScript berisi ID & pose.
4. **P2 — Scene 3D:** kubus/label mengikuti `Transform` dari `rvec/tvec`.
5. **P3 — Kalibrasi & polish:** kalibrasi kamera asli, smoothing pose, optimasi frekuensi deteksi.

---

## 3. Langkah-Langkah + Contoh Kode

### Fase 0 — Verifikasi tanpa ubah kode (5–10 menit)

1. Cetak marker ArUco **DICT_4X4_50** asli (mis. dari generator OpenCV, sisi 5 cm). Jangan pakai QR Code — tidak akan terdeteksi kode ini.
2. Jalankan Godot **dari terminal** (agar `LD_LIBRARY_PATH` OpenCV terbawa bila OpenCV dibangun dari source):
   ```bash
   source misc/set_opencv4.sh   # bila perlu
   godot --path demo
   ```
3. Amati Output log:
   - Tidak ada `[AR] Pemrosesan aktif` → kena masalah G1 (flag false).
   - Ada `[AR] PEMROSESAN NONAKTIF` → konfirmasi 100% G1.
   - Ada `[AR] Pemrosesan aktif` tapi tak ada `MARKER TERDETEKSI` → masalah marker (jenis/ukuran/pencahayaan).

### Fase 1 — Betulkan saklar + bug konversi (fondasi, wajib)

**1a. Set `show_processed = true` di scene** — edit `demo/Main2D.tscn`:

```ini
[node name="Sprite" type="Sprite" parent="."]
script = ExtResource( 1 )
show_processed = true
```

**1b. Sabuk pengaman di `demo/Main2D.gd`** — paksa aktif + reuse texture + label status:

```gdscript
extends Control

var _tex: ImageTexture

func _ready():
    _tex = ImageTexture.new()
    # Pastikan deteksi aktif walau properti di .tscn lupa dicentang:
    $Sprite.set_show_processed(true)
    $StatusLabel.text = "Menunggu marker DICT_4X4_50..."

func _on_Sprite_frame_updated(node, image):
    # Reuse SATU texture, jangan ImageTexture.new() tiap frame:
    _tex.create_from_image(image)
    $webcamView.texture = _tex
```

Tambahkan di `.tscn` sebuah `Label` bernama `StatusLabel` di bawah `webcamView` (untuk pesan status G5), dan sembunyikan worker:

```ini
[node name="Sprite" type="Sprite" parent="."]
script = ExtResource( 1 )
show_processed = true
visible = false
```

**1c. Perbaiki `cvMat_to_Image()`** — ganti blok `else` di `src/gd_opencv.cpp:135-141`:

```cpp
// BENAR: salin per baris dengan offset tujuan yang maju
else
{
    const int row_bytes = cv_rgb.cols * cv_rgb.channels();
    uint8_t *dst = bytes.write().ptr();
    for (int r = 0; r < cv_rgb.rows; ++r)
    {
        std::memcpy(dst + r * row_bytes, cv_rgb.ptr(r), row_bytes);
    }
}
```

**1d. Cache `DetectorParameters`** — di `src/own_opencv_processing.h` tambahkan member:

```cpp
// own_opencv_processing.h
#include <opencv2/aruco.hpp>
class OpenCVProcessing
{
private:
    cv::Ptr<cv::aruco::Dictionary> dictionary;
    cv::Ptr<cv::aruco::DetectorParameters> detector_params; // BARU
    // ... sisanya sama
};
```

```cpp
// own_opencv_processing.cpp — constructor
OpenCVProcessing::OpenCVProcessing()
{
    dictionary = cv::aruco::getPredefinedDictionary(cv::aruco::DICT_4X4_50);
    detector_params = cv::aruco::DetectorParameters::create(); // sekali saja
}
```

```cpp
// ... di process_image(), hapus create() per-frame, pakai member:
cv::aruco::detectMarkers(input, dictionary, markerCorners, markerIds,
                         detector_params, rejectedCandidates);
```

**1e. Rebuild + verifikasi:**

```bash
scons platform=linux -j$(nproc)
# pastikan demo/bin/x11/libgdopencvexample.so ter-update, lalu Run dan arahkan marker
# Harapan: log "[AR] MARKER TERDETEKSI! ID: ..." + kotak hijau di video
```

Kriteria lolos Fase 1: kotak + ID marker tergambar di `webcamView`. Ini **belum** AR 3D — baru bukti deteksi jalan.

### Fase 2 — Estimasi pose 3D (bukti visual `drawAxis`)

Tanpa ini, "objek 3D menempel" tidak mungkin. Butuh `cameraMatrix` + `markerLength` (ukuran sisi marker dalam meter — **tanyakan/ukur marker fisik, mis. 0.05**).

**2a. Tambah member kalibrasi** di `own_opencv_processing.h`:

```cpp
cv::Mat camera_matrix;
cv::Mat dist_coeffs;
float marker_length_m = 0.05f; // sesuaikan dengan cetakan fisik!
```

Inisialisasi pendekatan di constructor (nanti diganti hasil kalibrasi asli):

```cpp
// Perkiraan: fx = fy = 0.9 * width, cx = width/2, cy = height/2 (640x480)
camera_matrix = (cv::Mat_<double>(3, 3) <<
    576, 0, 320,
    0, 576, 240,
    0, 0, 1);
dist_coeffs = cv::Mat::zeros(5, 1, CV_64F);
```

**2b. Estimasi + gambar sumbu** — setelah `detectMarkers()` dan di dalam `if (marker_found)`:

```cpp
std::vector<cv::Vec3d> rvecs, tvecs;
cv::aruco::estimatePoseSingleMarkers(markerCorners, marker_length_m,
                                     camera_matrix, dist_coeffs,
                                     rvecs, tvecs);
for (size_t i = 0; i < markerIds.size(); ++i)
{
    cv::aruco::drawAxis(output, camera_matrix, dist_coeffs,
                        rvecs[i], tvecs[i], marker_length_m * 0.5f);
}
```

Kriteria lolos Fase 2: sumbu XYZ (merah/hijau/biru) menancap di tengah marker pada video. Jika sumbu muncul miring dengan benar saat kertas dimiringkan → pose sudah benar.

### Fase 3 — Plumbing pose ke Godot (kunci AR 3D)

Sinyal lama `frame_updated(node, image)` tidak cukup. Tambahkan sinyal pose di `src/gd_opencv.cpp::_register_methods`:

```cpp
// Setelah register_signal frame_updated:
register_signal<GDOpenCVExample>((char *)"marker_detected",
    "node", GODOT_VARIANT_TYPE_OBJECT,
    "ids", GODOT_VARIANT_TYPE_ARRAY,
    "translations", GODOT_VARIANT_TYPE_ARRAY,  // Array Vector3 (tvec meter)
    "rotations", GODOT_VARIANT_TYPE_ARRAY);    // Array Vector3 (rvec rad)
```

Di `_process()`, setelah `process_image`, emit pose (butuh `process_image` mengisi `last_rvecs/last_tvecs/last_ids` — simpan sebagai member `OpenCVProcessing` + getter, atau ubah return menjadi struct). Contoh emit untuk marker pertama:

```cpp
// gd_opencv.cpp — di dalam if (cap->read(frame)), setelah process_image:
Array ids, trans, rots;
for (size_t i = 0; i < own_opencv_code_object->last_ids.size(); ++i)
{
    ids.push_back(own_opencv_code_object->last_ids[i]);
    const auto &t = own_opencv_code_object->last_tvecs[i];
    const auto &r = own_opencv_code_object->last_rvecs[i];
    trans.push_back(Vector3(t[0], t[1], t[2]));
    rots.push_back(Vector3(r[0], r[1], r[2]));
}
if (ids.size() > 0)
    emit_signal("marker_detected", this, ids, trans, rots);
```

> Catatan implementasi: tambahkan `std::vector<int> last_ids; std::vector<cv::Vec3d> last_rvecs, last_tvecs;` sebagai member publik `OpenCVProcessing`, diisi di akhir `process_image()` (termasuk dikosongkan saat marker hilang agar kubus bisa disembunyikan).

Alternatif lebih cepat (tanpa ubah C++ dulu): kirim **pusat marker 2D** via sinyal, lalu di GDScript gerakkan `Sprite2D` overlay mengikuti — tapi ini bukan pose 3D sejati, hanya batu loncatan.

### Fase 4 — Scene 3D: kubus menempel di marker

1. Buat `demo/Main3D.tscn`: `Spatial(Main3D)` + `Camera` + `MeshInstance` (CubeMesh) + skrip `Main3D.gd`.
2. Hubungkan sinyal `marker_detected` ke `Main3D.gd`. Contoh konversi pose → transform (perlu penyesuaian sumbu OpenCV→Godot; mulai dari versi sederhana):

```gdscript
extends Spatial

# Ukuran marker (meter) harus sama dengan marker_length_m di C++
const MARKER_SIZE := 0.05

func _on_ARWorker_marker_detected(node, ids, translations, rotations):
    if ids.empty():
        $Cube.visible = false
        return
    $Cube.visible = true
    var t: Vector3 = translations[0]
    var r: Vector3 = rotations[0]
    # Pendekatan tahap 1: pakai translasi langsung (kamera di origin).
    # Tahap 2: bangun Basis dari rvec via Rodrigues di C++ lalu kirim Basis/Transform utuh.
    # Konversi sumbu OpenCV (Y bawah) ke Godot (Y atas): balik Y dan Z.
    $Cube.translation = Vector3(t.x, -t.y, -t.z)
    $StatusLabel.text = "Marker ID: %s" % str(ids[0])
```

3. Versi yang benar (disarankan setelah prototipe jalan): lakukan `cv::Rodrigues(rvec)` di C++, kirim `Transform`/`Basis` utuh lewat sinyal sebagai `Transform`, lalu di GDScript tinggal `$Cube.transform = godot_transform`. Ini menghindari gimbal/Euler dan menangani rotasi kertas miring dengan tepat.

Kriteria lolos Fase 4: kubus muncul saat marker terlihat, mengikuti posisi saat kertas digeser, dan hilang saat marker keluar frame (pakai event "Marker hilang" yang sudah ada untuk `visible = false`).

### Fase 5 — Kalibrasi & polish (setelah end-to-end jalan)

1. Kalibrasi kamera asli dengan papan catur (`cv::calibrateCamera`) → ganti `camera_matrix`/`dist_coeffs` perkiraan dengan hasil kalibrasi per resolusi (640x480). Tanpa ini pose bergoyang.
2. Smoothing pose (lerp / moving average) agar kubus tidak bergetar.
3. Optimasi: deteksi tiap 2–3 frame atau di thread bila CPU berat; `DetectorParameters` di-tuning (`adaptiveThreshWinSize`, `cornerRefinementMethod = CORNER_REFINE_SUBPIX`).
4. Multi-marker: pilih ID terkecil / ID target yang dikonfigurasi dari GDScript (`export var target_id`), bukan selalu index 0.
5. Penanganan tepi: kamera gagal dibuka → pesan di `StatusLabel`; `VideoCapture::release()` saat scene keluar.

---

## 4. Cara Menjalankan Tiap Verifikasi

```bash
# 1. Build ulang setelah setiap perubahan C++
scons platform=linux -j$(nproc)
ls -l demo/bin/x11/libgdopencvexample.so   # pastikan timestamp baru

# 2. Jalankan dari terminal agar path OpenCV terbawa
godot --path demo
# Amankan urutan log yang diharapkan:
#  [AR] OpenCVProcessing berhasil dibuat.
#  [AR] Pemrosesan aktif. Siap menerima ArUco Marker.
#  [AR] MARKER TERDETEKSI! ID: 7
```

---

## 5. Keputusan yang Masih Terbuka (butuh input user)

1. **Ukuran sisi marker fisik (cm)** — wajib untuk `marker_length_m` di Fase 2. Default sementara 5 cm.
2. **Konten AR** — kubus bawaan cukup untuk prototipe, atau mau model/text/URL tertentu?
3. **Strategi scene** — `Main2D` tetap untuk debug video + `Main3D` baru untuk AR, atau langsung migrasi ke 3D?
4. **Kalibrasi** — pakai perkiraan dulu (cepat) atau langsung kalibrasi papan catur (akurat)?
