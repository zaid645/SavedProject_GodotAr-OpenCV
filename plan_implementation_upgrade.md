# Plan Implementation Upgrade — ArUco + Natural Image Target (ORB)

> Dokumen ini adalah kelanjutan dari `plan_implementation.md` (jalur ArUco, sudah jalan:
> deteksi + pose + clamp + smoothing + spawn kubus).
> Upgrade ini menambahkan **jalur kedua: AR berbasis gambar bebas (natural image target)**
> yang berjalan **paralel berdampingan**, TANPA mengganggu / mengganti jalur ArUco.
> Status: **rencana (belum diimplementasi)**. Target Godot 3.x + OpenCV 4.6.0 + GDNative `.so` yang sama.
>
> ATURAN SCENE: file `.tscn` TIDAK BOLEH dibuat via kode (hasil generate tidak bisa dibuka
> di editor). File `.gd` boleh via kode. Semua pembuatan/pengubahan scene dilakukan MANUAL
> oleh manusia mengikuti `plan_implementation_upgrade-scene.md`.

# Plan Implementation Upgrade — ArUco + Natural Image Target (ORB)

> Dokumen ini kelanjutan dari `plan_implementation.md` (jalur ArUco: sudah jalan —
> deteksi + pose `rvec/tvec` + clamp + smoothing + spawn kubus via `ARMarkerSpawner`).
> Upgrade ini menambah **jalur kedua: AR berbasis gambar bebas (natural image target)**
> yang berjalan **paralel berdampingan**, TANPA mengganggu / mengganti jalur ArUco.
> Status: **rencana (belum diimplementasi)**. Target: Godot 3.x + OpenCV 4.6.0 + GDNative `.so` yang sama.

---

## 1. Prinsip Upgrade (non-negotiable)

1. **ArUco tetap utuh.** `src/own_opencv_processing.{h,cpp}` (dictionary DICT_4X4_50,
   `detectMarkers`, `estimatePoseSingleMarkers`, `last_ids/rvecs/tvecs`) dan node
   `ARSession` (`demo/global/ar.gd`) + `ARMarkerSpawner` (`demo/global/ar_marker_spawner.gd`)
   **tidak diubah perilakunya**. Jalur ArUco tetap jadi referensi stabil.
2. **Node baru untuk image, bukan modifikasi node ArUco.** Semua logika gambar tinggal di
   node/class baru (`ARImageSession`, `ARImageLibrary`, `ARImageSpawner` — lihat §4).
   Satu scene boleh memuat ArUco saja, image saja, atau keduanya (beda worker/frame budget).
3. **Sinyal image meniru bentuk sinyal ArUco** agar spawner & pola smoothing/clamp/hold
   yang sudah terbukti bisa dipakai ulang hampir tanpa ubah:
   `marker_detected(ids, translations, rotations)` → `image_detected(names, translations, rotations)`.
4. **Tanpa rebuild untuk Fase A.** Fase A (GDScript + scene + save/load) jalan di atas `.so`
   yang ada sekarang. Rebuild C++ hanya mulai Fase B (matcher ORB).

## 2. Arsitektur Saat Ini (ringkas, file nyata)

```
Webcam → cv::VideoCapture (src/gd_opencv.cpp)
  → OpenCVProcessing::process_image() (src/own_opencv_processing.cpp)
      detectMarkers → estimatePoseSingleMarkers → last_ids/rvecs/tvecs + overlay kotak/sumbu
  → sinyal marker_detected(ids, translations, rotations)
  → ARSession (demo/global/ar.gd): koreksi pose_scale, sync FOV, cache last_*
  → ARMarkerSpawner (demo/global/ar_marker_spawner.gd):
      marker_map {id:int → PackedScene} + clamp max_jump + lerp/slerp + hold_frames + debug_mode
```

Konfigurasi terkunci: OpenCV **4.6.0** (modul `features2d`, `calib3d`, `flann` tersedia — ORB/BFMatcher/
`findHomography`/`solvePnP` tidak butuh install baru), build via `SConstruct` (`Glob('src/*.cpp')`
→ file `.cpp` baru otomatis ikut ke-build), Godot 3.x GLES2, konversi gambar satu arah
(`cvMat_to_Image` ada; `Image_to_Mat` **belum ada** — harus dibuat di Fase B).

## 3. Arsitektur Target (dual pipeline)

```
                              ┌─ JALUR A (ada, utuh) ─────────────────┐
Webcam ─┬─ Worker ArUco ──→ ARSession ──→ ARMarkerSpawner ──→ objek per ID
        │
        └─ JALUR B (baru) ────────────────────────────────────────────┐
           Worker Image ──→ ARImageSession ──→ ARImageSpawner ──→ objek per NAMA
                ↑                              ↑
           ARImageLibrary (user://targets/)    save/load .png + .json (+ .yml opsional)
```

Aturan koeksistensi: **satu kamera aktif per scene** (dua `VideoCapture` = berat; `ARSession`
dan `ARImageSession` tidak boleh `auto_start` bersamaan di scene yang sama kecuali mode
hemat — lihat §10 Fase B4). Scene yang direncanakan: `ScanInput` (daftar target),
`Library` (lihat/edit/hapus), `ScanOutput` (kamera + spawn) — lihat §7.

<!--APPEND-->
## 4. Node Baru untuk Image (ArUco tidak disentuh)

Semua class baru, `class_name` agar bisa `add_child()` / `ClassName.new()`
(mengikuti aturan lokal proyek). File di `demo/global/`.

### 4.1 `ARImageSession` (`demo/global/ar_image_session.gd`, `extends Node`)

Pengganti `ARSession` khusus jalur gambar. Tanggung jawab: memegang worker image
(GDNative baru), meneruskan frame ke background, mengoreksi skala pose, sync FOV,
meng-emit sinyal image.

```gdscript
# Kontrak (belum implementasi — target API):
extends Node
class_name ARImageSession

signal frame_updated(image)                 # sama spt ARSession: utk background 2D/3D
signal image_detected(names, translations, rotations)  # paralel marker_detected
signal image_lost                           # semua target hilang
signal status_changed(text)

# Konfigurasi (cerminan ARSession + khusus image):
# camera_id, capture_width/height, show_processed, auto_start,
# auto_create_camera, video_enabled, video_distance, status_label_path,
# pose_scale (koreksi skala, dipakai ulang), target_width_m (default lebar fisik
# bila target tak menyimpan lebar sendiri), detect_every_n_frames (default 2),
# min_inliers (default 20), match_ratio (Lowe, default 0.75)
```

Perilaku: `start()/stop()/is_running()`, cache `last_names/last_translations/last_rotations`,
query `has_target(nama)`, `get_target_position(nama)`, `get_target_basis(nama)`,
`get_target_distance(nama)`, `status_text()`. Konversi sumbu OpenCV→Godot sama
persis (`Y/Z` dibalik) agar spawner tidak perlu tahu sumber pose.

### 4.2 `ARImageLibrary` (`demo/global/ar_image_library.gd`, `extends Node`)

Single source of truth untuk target tersimpan. Dipakai scene `ScanInput`, `Library`,
dan `ARImageSession` (untuk memuat DB ke C++).

```gdscript
# Kontrak (belum implementasi — target API):
extends Node
class_name ARImageLibrary

signal library_changed                      # tambah/hapus/edit -> UI refresh

# Format tiap entri (Dictionary):
# { "name": String (unik), "image_path": String (user://targets/<nama>.png),
#   "width_m": float (lebar fisik, WAJIB utk pose), "keypoints": int (saat input),
#   "scene_path": String (PackedScene opsional, boleh kosong = fallback kubus) }

func add_target(image: Image, name: String, width_m: float, scene_path := "") -> String  # "" = OK, else pesan error
func remove_target(name: String) -> void
func list_targets() -> Array                 # Array[Dictionary], urut nama
func get_target(name: String) -> Dictionary
func save() -> void                          # tulis index.json + .png
func load() -> void                          # baca index.json saat start
```

Validasi `add_target` (wajib, mencegah target tak-ter-track): tolak bila `keypoints < 150`
(estimator dihitung di C++ saat input — lihat §10 Fase B1), tolak nama duplikat/kosong,
tolak `width_m <= 0`. Gambar disimpan **grayscale, lebar maks 480px** (preprocessed,
bukan asli full-res — lihat §6).

### 4.3 `ARImageSpawner` (`demo/global/ar_image_spawner.gd`, `extends Spatial`)

Kembaran `ARMarkerSpawner` untuk kunci string. Menempelkan `PackedScene` per **nama target**
di pose target; fallback kubus warna-per-nama bila `scene_path` kosong.

```gdscript
# Kontrak (belum implementasi — target API):
extends Spatial
class_name ARImageSpawner

signal spawned(name, instance)
signal despawned(name)

export var auto_create_session: bool  # buat ARImageSession sendiri bila tak ada
export var session_node: NodePath     # node ARImageSession; kosong = cari otomatis
export var target_map: Dictionary     # {nama:String -> PackedScene} (override per-scene;
                                      # bila kosong, pakai scene_path dari library)
export var smooth_factor, smooth_rot, hold_frames, max_jump  # SAMA default & makna
                                                             # dgn ARMarkerSpawner (clamp, bukan freeze)
export var fallback_cube: bool
export var debug_mode: bool           # true = semua target tampil + status; false = hanya yg ada scene valid
export var status_label_path: NodePath
```

Logika penempelan = salinan `ARMarkerSpawner._on_markers` dengan kunci `String`
(snap saat spawn → clamp `max_jump` ke arah pengukuran → `lerp` posisi + `slerp` rotasi →
`hold_frames` saat hilang). Handler sinyal: `_on_images(names, translations, rotations)`
(tanpa argumen `_node` — mengikuti pola sinyal GDScript `ARSession`, bukan sinyal mentah C++).

---

## 5. Format Penyimpanan (save dan load)

Direktori: `user://targets/` (portabel per-platform, tidak masuk git).

```
user://targets/
  index.json            # daftar entri (skema di bawah)
  <nama>.png            # PREPROCESSED (grayscale, lebar <=480px) utk matching + thumbnail
  <nama>.yml            # descriptor ORB via cv::FileStorage (opsional, Fase B3)
```

`index.json` contoh:

```json
{
  "targets": [
    { "name": "poster_kopi", "image_path": "user://targets/poster_kopi.png",
      "width_m": 0.20, "keypoints": 430, "scene_path": "res://models/Kursi.tscn" },
    { "name": "logo_kampus", "image_path": "user://targets/logo_kampus.png",
      "width_m": 0.10, "keypoints": 310, "scene_path": "" }
  ]
}
```

Catatan: `scene_path` kosong = fallback kubus (debug) / diabaikan (produksi,
`debug_mode=false`). Descriptor tidak wajib disimpan permanen: cukup `.png`
preprocessed; `.yml` dihitung ulang saat input dan ditulis ulang saat load bila hilang.

---

## 6. Alternatif Gambar: Rekomendasi (bukan gambar asli mentah)

| Opsi | Isi | Rekomendasi |
|---|---|---|
| A. ArUco-framed image | Gambar bebas + border ArUco | REKOMENDASI utk stabilitas: pose seakurat ArUco sekarang, tanpa matcher baru. Usaha 10 persen, hasil 90 persen. |
| B. Preprocessed grayscale <=480px | Gray + downscale + equalizeHist + blur ringan | WAJIB bila pilih ORB. Full-res asli HANYA utk thumbnail, tidak pernah dipakai matching. |
| C. AKAZE | Deskriptor AKAZE, tetap free di 4.6 | Cadangan Fase C bila ORB kurang invarian skala/rotasi. |
| D. ID-tetap sebagai jangkar | ArUco ID = pose; gambar = label visual | Nol rebuild, mapping GDScript saja. Kehilangan fitur scan gambar apa pun. |
| E. SIFT | -- | TIDAK disarankan utk loop per-frame (terlalu berat di 30fps). |

Keputusan dokumen ini: jalur ORB memakai opsi B (wajib), opsi A jalan tengah cepat,
opsi C cadangan Fase C, opsi D fallback bila matcher belum siap.

---

## 7. Tiga Scene Baru (kontrak; .tscn HANYA manual di editor)

Aturan proyek: `.gd` boleh via kode, `.tscn` TIDAK BOLEH via kode (file generate
tidak bisa dibuka di editor). Instruksi pembuatan manual ada di
`plan_implementation_upgrade-scene.md` (`scene_implementation.md` hanya utk jalur ArUco lama).

1. ScanInput.tscn: preview TextureRect (kamera ATAU FileDialog) + LineEdit nama +
   SpinBox lebar cm + tombol Ambil dan Simpan -> ARImageLibrary.add_target() ->
   status jumlah keypoint (OK 430 / DITOLAK: terlalu polos, ganti gambar).
2. Library.tscn: GridContainer thumbnail (<nama>.png) + nama + keypoint + lebar cm +
   scene terpasang; tombol Hapus -> remove_target(); tombol Ganti Scene -> FileDialog
   .tscn -> update scene_path. Refresh via sinyal library_changed.
3. ScanOutput.tscn: seperti Main3D versi image: ARImageSession + ARImageSpawner
   (target_map diisi dari library saat _ready) + Camera + background video +
   StatusLabel. Run -> target terlihat -> scene menempel; hilang > hold_frames -> hide+free.

---
## 8. Tantangan dan Kekurangan (jujur, spesifik proyek ini)

1. Stabilitas turun 2-3x vs ArUco. findHomography dari keypoint noise jauh lebih
   berisik daripada 4 sudut ArUco yang tegas. Clamp + smoothing warisan ArUco akan
   bekerja lebih keras; ekspektasi goyang disetel sejak awal.
2. CPU berat. ORB detect + match per N target per frame jauh di atas detectMarkers.
   Kasar: 10-15 fps utk 3-5 target di laptop bila tiap frame. Wajib hemat (Fase B4):
   detect_every_n_frames=2-3, nfeatures=500-750, downscale. Library >20 butuh
   preseleksi (vocabulary tree) = Fase D, di luar lingkup awal.
3. Konversi dua arah belum ada. Image_to_Mat (file/kamera ke matcher) harus dibuat;
   cvMat_to_Image yang ada dipakai ulang utk background. Salah format RGB/BGR/gray =
   match gagal total tanpa error jelas; uji konversi dulu sebelum matcher.
4. Target layar HP = musuh ORB. Glare + moire + refresh (pengalaman ArUco dari layar
   HP sudah membuktikan). Target cetak kertas jauh lebih baik; wajib dicatat di UI.
5. Lebar fisik wajib diinput. Tanpa width_m, solvePnP tak punya skala (pelajaran
   marker_length/pose_scale di ArUco terulang).
6. Dua VideoCapture = konflik. ARSession + ARImageSession jangan auto_start bersamaan.
   Gabungan butuh frame-sharing (satu capture, dua proses) = Fase D.
7. Gambar polos tak bisa di-track. Keypoint < ambang harus DITOLAK saat input dengan
   pesan jelas, bukan gagal misterius saat scan.
8. Risiko mobile (lihat IMPLEMENTATION_EXPORD.MD). Tambahan .cpp + link ORB
   memperbesar .so; kamera Android via C++ beda dari desktop. Stabilkan desktop dulu.

---

## 9. Kriteria Lolos Tiap Fase

1. Fase A: daftar target dari kamera/file -> tersimpan user://targets/ -> tampil di
   Library -> hapus/edit scene jalan; tanpa rebuild .so; ArUco tetap seperti semula.
2. Fase B1-B2: 1 target kertas -> image_detected terpancar -> kubus fallback menempel +
   ikut miring; ScanInput tampil jumlah keypoint; gambar polos ditolak dgn pesan jelas.
3. Fase B3-B4: 3-5 target, fps >= 15 di laptop; restart -> load .yml tanpa re-ekstrak;
   frame budget terukur di log.
4. Fase C: kalibrasi pose_scale jalur image (jarak label vs penggaris, prosedur sama
   seperti ArUco); sisa goyang didokumentasikan sebagai batas motion-blur.

---
## 10. Rencana Pengerjaan (berfase, ArUco utuh)

### Fase A - GDScript + scene + save/load (TANPA rebuild, TANPA ubah ArUco)

- A1. demo/global/ar_image_library.gd (ARImageLibrary): skema section 5 + validasi
  nama/duplikat/width_m + tulis/baca index.json + .png via Image save_png +
  sinyal library_changed. (Keypoint sungguhan di B1; sementara varians sederhana.)
- A2. demo/global/ar_image_spawner.gd (ARImageSpawner, extends Spatial): salinan pola
  ARMarkerSpawner kunci String + target_map {nama -> PackedScene} + clamp/lerp/slerp/
  hold/debug/fallback kubus warna-per-nama (hash nama ke hue).
- A3. Stub demo/global/ar_image_session.gd (ARImageSession): API section 4.1 dgn
  backend sementara (tanpa deteksi) agar scene A4 bisa disusun dan di-run.
- A4. Kontrak + panduan scene ScanInput/Library/ScanOutput (tambah ke
  plan_implementation_upgrade-scene.md oleh manusia di editor; JANGAN buat .tscn via kode).
- A5. Verifikasi kriteria 9.1 + regression ArUco (Main3D tetap spawn kubus).

### Fase B - C++ matcher ORB (rebuild .so, file BARU, ArUco lama tak diubah)

- B1. src/image_target_db.{h,cpp} (BARU): ORB create(nfeatures=750) + addTarget(png
  grayscale, width_m) + hitung keypoints.size() utk validasi + save/load via
  cv::FileStorage (.yml) + getTargetList(). Plus helper Image_to_Mat ATAU terima
  path -> cv::imread (pilih SATU).
- B2. src/gd_image_detector.{h,cpp} (BARU, worker GDNative GDImageDetector TERPISAH
  dari GDOpenCVExample): VideoCapture sendiri + tiap detect_every_n_frames:
  ORB detectAndCompute(frame) -> per target BFMatcher(Hamming) + knnMatch(k=2) +
  Lowe 0.75 -> findHomography(RANSAC) -> inliers >= min_inliers(20) -> solvePnP
  4 sudut (width_m + aspek) -> last_names/rvecs/tvecs -> sinyal
  image_detected(names, translations, rotations) + overlay opsional. Kosong bila
  tak ada yg lolos (spawner grace-frames sendiri).
- B3. Wiring ARImageSession ke worker baru (ganti stub A3): start/stop, muat DB dari
  ARImageLibrary -> worker.load_db(), teruskan frame_updated + image_detected,
  koreksi pose_scale, sync FOV (fx = 0.9*width*pose_scale, rumus sama).
- B4. Mode hemat: detect_every_n_frames default 2, downscale lebar 480, batas
  nfeatures, log frame-budget ([IMG] match N target: X ms). Verifikasi 9.2-9.3.
- Aturan: JANGAN sentuh own_opencv_processing.*, gd_opencv.*, ar.gd,
  ar_marker_spawner.gd selain penambahan non-breaking (lebih baik duplikasi kecil
  daripada kopling).

### Fase C - Kalibrasi dan polish jalur image

- C1. Kalibrasi pose_scale jalur image (jarak label vs penggaris, prosedur sama ArUco).
- C2. Tuning per-jalur: smooth image LEBIH RENDAH (6-8), max_jump LEBIH KECIL (0.20),
  hold LEBIH BESAR (8-10) dari default ArUco; ukur, jangan tebak.
- C3. Cadangan AKAZE (ganti ORB create -> AKAZE create, ukur ulang fps/inlier).
  SIFT tetap tidak dipakai (section 6E).
- C4. Tabel jenis gambar ke hasil (tekstur kaya OK / minimalis ditolak / layar goyang /
  kertas stabil) + panduan cetak target.

### Fase D - di luar lingkup (dicatat)

Frame-sharing satu VideoCapture utk ArUco+image; vocabulary tree utk library >20;
Android (lihat IMPLEMENTATION_EXPORD.MD + tantangan 8.8).

---

## 11. Keputusan Terbuka (input sebelum Fase B)

1. Pilih opsi gambar (section 6): B-full ORB, A-framed cepat, atau D-jangkar tanpa C++?
2. Batas library: berapa target maks real-time di laptop (ukur B4; rancang default 5)?
3. Sumber input prioritas: kamera dulu atau pilih-file dulu (mempengaruhi B1:
   perlu Image_to_Mat vs cukup imread(path))?
4. Konten per target: fallback kubus cukup, atau tiap target wajib .tscn sendiri?
5. Gabung ArUco+image satu scene? Bila ya -> Fase D (frame-sharing), bukan default.
