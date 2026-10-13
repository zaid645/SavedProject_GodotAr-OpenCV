# IMPLEMENTATION_AR — Menambahkan AR ke Scene Baru (bag. 1)

Panduan memakai autoload **`AR`** (`demo/global/ar.gd`) agar scene 3D
maupun 2D mana pun bisa menampilkan kamera + objek AR **tanpa membuat
`ARWorker` sendiri**. Fokus utama: scene 3D; pola 2D sebagai bonus.

Alur arsitektur:

```
GDNative worker (C++) --frame_updated/marker_detected--> AR (autoload)
  --frame_updated/marker_detected/marker_lost/status_changed--> scene kamu
```

---

## 1. Ganti pendekatan: Node, bukan autoload

`AR` **tidak lagi jadi autoload global**. Sekarang ia sebuah **node** yang kamu
tambahkan sendiri ke scene yang membutuhkan AR:

- `ar.gd` → `class_name ARSession` (pemrosesan kamera + deteksi marker).
- `ar_marker_spawner.gd` → `class_name ARMarkerSpawner` (spawn objek per ID).

Kenapa node, bukan autoload:

| | Node `ARSession` (kini) | Autoload `AR` (lama) |
|---|---|---|
| Ruang lingkup | Hanya scene yg punya node itu | Seluruh aplikasi |
| Cocok untuk | **Scene tertentu** (rekomendasimu) | AR di mana-mana tanpa setup |
| Cara pakai | Taruh node / `add_child(ARSession.new())` | Daftar sekali di Project Settings |
| Banyak scene AR | 1 sesi per scene (kamera mati saat keluar) | 1 sesi global (perlu `stop()` saat pindah) |

Dengan node, scene non-AR sama sekali tidak tersentuh — sesuai keinginanmu.
(Bila nanti ingin tetap memakai autoload, lihat bagian 5.)

Konfigurasi default di `ARSession` (bisa diubah dari Inspector):
`camera_id=0`, `640x480`, `show_processed=true`, `marker_length=0.05`,
`auto_start=true`.

## 2. Sinyal & API yang disediakan `ARSession`

| Sinyal | Argumen | Kapan dipancarkan |
|---|---|---|
| `frame_updated` | `(image: Image)` | Tiap frame kamera (reuse untuk background video) |
| `marker_detected` | `(ids, translations, rotations)` | Tiap frame termasuk kosong (agar consumer bisa grace-frames) |
| `marker_lost` | `()` | Sekali saat transisi terlihat → hilang total |
| `status_changed` | `(text: String)` | Perubahan status internal AR |

Fungsi penting: `start()` / `stop()` / `is_running()`,
`set_camera_id(n)`, `set_show_processed(v)`, `set_marker_length(m)`,
`get_video_texture()`, `has_marker(id)`, `get_marker_index(id)`,
`get_marker_position(id)` (sudah konversi sumbu OpenCV→Godot),
`get_marker_basis(id)`, `get_marker_tilt_deg(id)`,
`status_text()`, `basis_from_rvec(r)` (static).

> Peringatan penamaan: JANGAN membuat fungsi bernama `get_index()`, `get_name()`,
> `get_class()`, dll. Itu method bawaan `Node`/`Object` — kalau ditimpa dengan
> signature berbeda, editor menampilkan
> `error 146: The function signature doesn't match the parent.`
> Pakai awalan khusus, mis. `get_marker_index()`.

Aturan ID: `id = -1` = "marker pertama / apa saja";
`id >= 0` = ID ArUco spesifik (untuk multi-model).

## 3. Model pemakaian: `ARSession` + `ARMarkerSpawner` (paling cepat)

Dua file utama (sama-sama `class_name`, BUKAN autoload):

| File | class_name | Peran |
|---|---|---|
| `demo/global/ar.gd` | `ARSession` | Pemrosesan AR: kamera + deteksi marker. Taruh 1x per scene. |
| `demo/global/ar_marker_spawner.gd` | `ARMarkerSpawner` | Memunculkan scene objek sesuai ID marker. Node terpisah; tidak tahu soal GDNative. |

Langkah manual (TIDAK ada scene otomatis — ini memang konsepmu):

1. Scene 3D baru: root `Spatial` + `Camera` + (opsional) `Label StatusLabel`.
2. Tambahkan node **`ARSession`** (ketik di Add Node → karena ada `class_name`,
   atau `add_child(ARSession.new())` dari kode). `auto_start=true` → kamera nyala.
3. Tambahkan node **`ARMarkerSpawner`**. Di Inspector:
   - `session_node`: seret node `ARSession` tadi (boleh dikosongkan;
     spawner mencari sendiri, `auto_create_session=true` bisa membuatnya).
   - `marker_map` (Dictionary): **key = ID ArUco** (mis. `7`),
     **value = PackedScene** objekmu (mis. `Kursi.tscn` — buat via
     Scene → Save Branch as Scene).
   - `fallback_cube = true` → ID tak ada di map tetap muncul kubus warna unik.
   - `status_label_path` (opsional): seret node Label.
4. Run. Marker ID 7 terlihat → `Kursi` muncul menempel di marker + ikut miring;
   marker hilang > `hold_frames` → objek disembunyikan lalu di-free.

Ya — ArUco memang "berisi ID" (DICT_4X4_50 = ID 0–49). Node `ARSpawner`
memetakan **ID → scene objek**, persis seperti yang kamu bayangkan.


### 3a. Yang ARSession buat OTOMATIS (tanpa setup manual)

| Node | Export pengatur | Bila dinonaktifkan |
|---|---|---|
| `ARWorker` (Sprite, GDNative) | — | selalu dibuat di `start()` |
| `ARCamera` (Camera) | `auto_create_camera` | pakai Camera milik scene-mu (dicari otomatis) |
| `VideoQuad` (MeshInstance) | `video_enabled`, `video_distance` | tampilkan video sendiri (mis. `TextureRect` 2D) |
| Label status | `status_label_path` (NodePath) | **kosong = tetap jalan**; status hanya lewat sinyal `status_changed` |
| Skala pose | `pose_scale` (ARSession) | `1.0` = tanpa koreksi; lihat bagian 8 untuk kalibrasi |
| Mode tampilan | `debug_mode` (ARSpawner) | `false` = hanya scene terdaftar; lihat bagian 7 |

Perhatikan di foto uji kamu: kubus tersebar jauh ke luar padahal marker di
tengah — itu ciri khas **kesalahan skala**, bukan smoothing. Kerjakan
kalibrasi `pose_scale` di bagian 8 lebih dulu sebelum menurunkan smoothing.

Jadi untuk scene 3D paling minimal: `Spatial` root + node `ARSession` +
node `ARMarkerSpawner` → **Camera dan video jadi sendiri**. Tambahkan node
`Label` lalu seret ke `status_label_path` (di ARSession maupun ARSpawner)
hanya bila ingin lihat status; dikosongkan tidak error.

### 3b. Contoh skrip sendiri (tanpa ARSpawner)

Bila ingin logika sendiri, hubungkan ke node `ARSession` (bukan autoload):

```gdscript
extends Spatial

var _ar: ARSession
var _cube: MeshInstance

func _ready():
    # Cara 1: node ARSession sudah ada di scene -> ambil
    # Cara 2: buat dari kode (semua node pendukung ikut otomatis)
    _ar = ARSession.new()
    add_child(_ar)               # auto_start=true -> kamera + video quad nyala
    _ar.connect("marker_detected", self, "_on_markers")
    _ar.connect("marker_lost", self, "_on_lost")

    _cube = MeshInstance.new()
    var box := BoxMesh.new()
    box.size = Vector3(0.05, 0.05, 0.05)
    _cube.mesh = box
    _cube.visible = false
    add_child(_cube)

# CATATAN: sinyal ARSession mengirim 3 argumen (tanpa node), beda dgn sinyal C++
# yang mengirim 4 argumen (node, ids, translations, rotations).
func _on_markers(ids: Array, translations: Array, rotations: Array) -> void:
    if ids.empty():
        _cube.visible = false
        return
    var t: Vector3 = translations[0]
    _cube.translation = Vector3(t.x, -t.y, -t.z)
    _cube.transform.basis = ARSession.basis_from_rvec(rotations[0])
    _cube.visible = true

func _on_lost() -> void:
    _cube.visible = false
```

Bila salah satu tanda tangan tidak cocok, editor mengeluarkan:
`emit_signal: Error calling method from signal ... Method expected 4 arguments, but called with 3`
— artinya handler masih memakai bentuk sinyal C++ (`node` di depan).
Perbaiki dengan membuang argumen pertama `_node`.

Kenapa quad, bukan `TextureRect` fullscreen: Control selalu digambar DI ATAS
3D dalam satu viewport sehingga menutupi model. Quad punya depth yang benar.
Di scene 2D, node 3D milik ARSession tidak ter-render sehingga tidak mengganggu.
---

## 4. Scene 2D (debug video saja)

Root `Control` + `TextureRect webcamView` + `Label StatusLabel`; sesi AR dibuat
dari kode (node 3D milik ARSession tidak ter-render di scene 2D, aman):

```gdscript
extends Control

var _tex: ImageTexture
var _ar: ARSession

func _ready():
    _tex = ImageTexture.new()
    _ar = ARSession.new()
    _ar.video_enabled = false  # 2D pakai TextureRect sendiri, bukan VideoQuad
    add_child(_ar)
    _ar.connect("frame_updated", self, "_on_frame")
    _ar.connect("marker_detected", self, "_on_markers")
    _ar.connect("status_changed", self, "_on_status")

func _on_frame(image):
    if image == null:
        return
    _tex.create_from_image(image)
    $webcamView.texture = _tex

func _on_markers(ids: Array, _t: Array, _r: Array) -> void:
    if ids.empty():
        $StatusLabel.text = "Menunggu marker..."
    else:
        $StatusLabel.text = "Marker ID: %s" % str(ids[0])

func _on_status(text: String) -> void:
    $StatusLabel.text = text
```

Kenapa `class_name` wajib di tiap script: itulah yang membuat `ARSession.new()`
serta entri "Add Node → ARSession" tersedia tanpa menulis path file.

## 5. Migrasi scene lama (Main2D / Main3D)

- `MainAR.gd` / `Main2D.gd` yang ada **tetap jalan** (memakai worker C++ via
  koneksi sinyal di editor) — tidak wajib diubah.
- Perbedaan tanda tangan sinyal yang perlu diingat:
  - Sinyal **C++** (`gd_opencv.gdns`): `frame_updated(node, image)`,
    `marker_detected(node, ids, translations, rotations)` → handler butuh 4 argumen.
  - Sinyal **ARSession**: `frame_updated(image)`,
    `marker_detected(ids, translations, rotations)` → handler butuh 3 argumen.
- Bila ingin migrasi ke node ARSession: hapus node worker (`Sprite`/`ARWorker`)
  dari `.tscn` beserta koneksinya, ganti dengan node `ARSession`
  (+ `ARMarkerSpawner` bila ingin). Jangan jalankan worker ganda dalam satu scene
  (2 `VideoCapture` = berat).
- `MainAR.gd` tetap rujukan pola matang (grace-frames, `max_jump`, smoothing
  terpisah, warna per ID) — semua itu sudah ada di `ARMarkerSpawner`.

## 6. Troubleshooting

| Gejala | Penyebab umum | Perbaikan |
|---|---|---|
| `Identifier "ARSession" not declared` | `class_name` belum terbaca | Restart editor (scan class global) |
| `Identifier "ARMarkerSpawner" not declared` | idem | Restart editor; cek file `ar_marker_spawner.gd` ada |
| `emit_signal: ... expected 4 arguments, but called with 3` | Handler masih bentuk sinyal C++ (`_node` di depan) | Buang argumen `_node` → `_on_markers(ids, translations, rotations)` |
| `error 146: signature doesn't match the parent` | Nama fungsi bentrok method bawaan (`get_index`, `get_name`, …) | Ganti nama, mis. `get_marker_index()` |
| Marker tak memunculkan apa pun | `marker_map` kosong / ID salah / `fallback_cube` off | Isi `marker_map` (atau `add_marker(7, load(...))`); coba `fallback_cube=true` |
| Layar hitam, tanpa log `[AR]` | Sesi belum jalan / `.so` lama | `auto_start=true`; cek `gd_opencv.gdns`, rebuild `.so`, restart editor |
| `PEMROSESAN NONAKTIF` | `show_processed=false` | Set `show_processed=true` di node ARSession |
| Kubus meleset dari marker | FOV kamera beda dgn fx OpenCV | `ARSession` menyetel FOV otomatis (~45° utk 640×480); jangan timpa manual |
| Kubus kedip | Deteksi kedip (glare layar HP) | `hold_frames=12` (default ARSpawner) |
| 2 kamera terbuka | Worker lama + ARSession jalan bersamaan | Hapus salah satunya (bagian 5) |

---

## 7. Debug mode `ARMarkerSpawner`

`export var debug_mode: bool = true` mengatur seberapa "banyak bicara" spawner:

| `debug_mode` | Perilaku |
|---|---|
| `true` (default) | Semua marker terdeteksi dapat objek; ID tak terdaftar dapat **kubus fallback** warna unik per ID; `StatusLabel` diperbarui (ID, jarak, derajat) |
| `false` | Hanya ID yang ada di `marker_map` yang memunculkan scene-nya, di lokasi marker. ID lain **diabaikan total** (tanpa kubus, tanpa status) |

Jadi mode `false` = tampilan produksi (bersih, hanya konten valid);
mode `true` = pengembangan (semua terlihat + status). Keduanya memakai
smoothing, grace-frames, dan pose yang sama.

---

## 8. Kalibrasi cepat `pose_scale` (mengatasi kubus meleset)

### 8a. Gejala & penyebab

Kubus melesat/menjauh dari marker (terutama saat kamera digerakkan) hampir
selalu karena **kesalahan SKALA**, bukan smoothing. Penyebabnya dua dan
sama-sama bersifat linear:

1. **`marker_length` tidak sesuai ukuran asli.** Marker di layar HP hampir
   pasti bukan 5 cm (biasanya 2–3 cm). Karena pose OpenCV berskala linear
   terhadap `marker_length`, jarak hasil estimasi jadi beberapa kali lebih besar.
2. **`fx` perkiraan** (`0.9 × width`) tidak sama dengan `fx` webcam asli.

Keduanya bisa dikoreksi dengan **satu angka**: `pose_scale` di node `ARSession`.
Apa pun penyebabnya, hasilnya identik: kalikan pose dengan `pose_scale`.

### 8b. Prosedur (2 menit, tanpa alat)

1. Pastikan `debug_mode = true` dan `status_label_path` menunjuk ke Label
   (di `ARMarkerSpawner` maupun `ARSession`) → label menampilkan jarak, mis.
   `ID [7] | 0.83 m | miring 4°`.
2. **Ukur jarak nyata** marker ke lensa kamera dengan penggaris, mis. **0.30 m**.
3. Baca jarak pada label, mis. `0.83 m` (terlalu besar).
4. Hitung: `pose_scale = jarak_nyata / jarak_terbaca = 0.30 / 0.83 = 0.36`.
5. Set `pose_scale = 0.36` di node `ARSession` (Inspector), atau dari kode:
   `$ARSession.set_pose_scale(0.36)`.
6. Ulangi langkah 2–5 pada jarak berbeda (mis. 0.20 m dan 0.50 m); ambil nilai
   yang membuat label paling mendekati ukuran di kedua jarak.
7. Cek visual: kubus kini menempel di marker walau kamera digeser.

FOV kamera **ikut dikoreksi otomatis** (`fx_eff = 0.9 × width × pose_scale`),
sehingga posisi dan proyeksi tetap konsisten — tidak perlu menyentuh
`Camera.fov` manual.

> Alternatif tanpa angka koreksi: ukur sisi hitam marker di layar (cm), lalu
> set `marker_length` di meter (mis. 2.5 cm → `0.025`). Hasilnya setara;
> `pose_scale` lebih praktis bila ukurannya sulit diukur tepat.

### 8c. Bila masih meleset (urutan tindakan)

| Langkah | Aksi | Efek |
|---|---|---|
| 1 | `pose_scale` sesuai 8b | Memperbaiki ~90% kasus (skala) |
| 2 | Turunkan `smooth_factor` ke 3–5, `smooth_rot` ke 5 | Mengurangi goyang saat kamera bergerak (tambah sedikit lag) |
| 3 | Periksa `max_jump` (0.15 m) | Bila kubus "nyangkut" saat digerak cepat, naikkan ke 0.25 |
| 4 | Kalibrasi kamera asli (`cv::calibrateCamera`, papan catur) | Perbaikan pasti `fx/fy/cx/cy` — menyusul bila 1–3 belum cukup |
| 5 | Webcam 30 fps + rolling shutter | Bukan config: gerakan cepat memang blur; kurangi kecepatan gerak |

Catatan: getaran yang **muncul hanya saat kamera digerak cepat** sebagian besar
adalah motion blur + latensi capture, bukan bug — `hold_frames` mencegah kubus
hilang, `pose_scale` mencegah meleset.



