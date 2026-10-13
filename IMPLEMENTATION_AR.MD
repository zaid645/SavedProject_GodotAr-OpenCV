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


```gdscript
extends Spatial

var _tex: ImageTexture
var _quad: MeshInstance
var _cube: MeshInstance

func _ready():
    _tex = ImageTexture.new()
    AR.connect("frame_updated", self, "_on_frame")
    AR.connect("marker_detected", self, "_on_markers")
    AR.connect("marker_lost", self, "_on_lost")
    AR.connect("status_changed", self, "_on_status")
    AR.start()
    $Camera.fov = rad2deg(2.0 * atan(480.0 / (2.0 * (0.9 * 640.0))))  # ~45
    _cube = MeshInstance.new()
    var box := BoxMesh.new()
    box.size = Vector3(0.05, 0.05, 0.05)
    _cube.mesh = box
    _cube.visible = false
    add_child(_cube)

func _on_frame(image):
    if image == null:
        return
    _tex.create_from_image(image)
    if _quad == null:
        _quad = _make_video_quad($Camera, _tex)

func _on_markers(ids, translations, rotations):
    if ids.empty():
        _cube.visible = false
        return
    var t: Vector3 = translations[0]
    _cube.translation = Vector3(t.x, -t.y, -t.z)
    _cube.transform.basis = AR.basis_from_rvec(rotations[0])
    _cube.visible = true
    $StatusLabel.text = AR.status_text()

func _on_lost():
    _cube.visible = false

func _on_status(text):
    $StatusLabel.text = text

func _make_video_quad(cam: Camera, tex: Texture) -> MeshInstance:
    var dist := 1.0
    var hh := dist * tan(deg2rad(cam.fov * 0.5))
    var hw := hh * (640.0 / 480.0)
    var q := QuadMesh.new()
    q.size = Vector2(hw * 2.0, hh * 2.0)
    var m := SpatialMaterial.new()
    m.flags_unshaded = true
    m.albedo_texture = tex
    m.emission_enabled = true
    m.emission = Color(1, 1, 1)
    m.emission_texture = tex
    var mi := MeshInstance.new()
    mi.mesh = q
    mi.set_surface_material(0, m)
    cam.add_child(mi)
    mi.translation = Vector3(0, 0, -dist)
    return mi
```

Kenapa quad, bukan `TextureRect` fullscreen: Control selalu digambar DI ATAS
3D dalam satu viewport sehingga menutupi model. Quad punya depth yang benar.
Ganti `AR` jadi `_ar` (node) di contoh tersebut — pola koneksi sama, cuma
sumbernya node `ARSession`, bukan autoload.


---

## 4. Membuat `ARSession` dari kode (bila tak mau tambah node manual)

```gdscript
func _ready():
    var ar := ARSession.new()
    ar.capture_width = 640
    ar.capture_height = 480
    ar.marker_length = 0.05
    add_child(ar)  # auto_start=true -> kamera langsung nyala
    ar.connect("marker_detected", self, "_on_markers")

func _on_markers(ids, translations, rotations):
    if ids.empty():
        return
    var t: Vector3 = translations[0]
    $Cube.translation = Vector3(t.x, -t.y, -t.z)
    $Cube.transform.basis = ARSession.basis_from_rvec(rotations[0])
```

Kenapa `class_name` wajib di tiap script: itu yang membuat `ARSession.new()`
dan node "Add Node → ARSession" tersedia di editor tanpa path file.

## 5. Bila tetap ingin autoload (opsional)

1. Project Settings → Autoload → `res://global/ar.gd`, nama `AR`, Enabled.
2. Di skrip: `const AR := get_node("/root/AR")`, atau pakai `class_name`.
3. JANGAN jalankan autoload + node ARSession sekaligus (2 kamera = berat).

## 6. ARMarkerSpawner — scene objek per ID (tanpa sentuh ArUco)

Root `Control` + `TextureRect webcamView` + `Label StatusLabel`, script:

```gdscript
extends Control
var _tex: ImageTexture
func _ready():
    _tex = ImageTexture.new()
    AR.connect("frame_updated", self, "_on_frame")
    AR.connect("marker_detected", self, "_on_markers")
    AR.start()
func _on_frame(image):
    if image == null:
        return
    _tex.create_from_image(image)
    $webcamView.texture = _tex
func _on_markers(ids, _t, _r):
    if ids.empty():
        $StatusLabel.text = "Menunggu marker..."
    else:
        $StatusLabel.text = "Marker ID: %s" % str(ids[0])
```

---

## 5. Migrasi scene lama (Main2D / Main3D)

- `MainAR.gd` / `Main2D.gd` yang ada **tetap jalan** (membawa worker sendiri)
  — tidak wajib diubah.
- Bila ingin migrasi ke autoload: hapus node worker (`Sprite`/`ARWorker`)
  dari `.tscn` + hapus koneksi sinyalnya di editor, lalu hubungkan script ke
  sinyal `AR` seperti contoh di atas. Jangan jalankan worker ganda
  (2 `VideoCapture` = berat); pilih satu pola per scene.
- `MainAR.gd` sudah berisi pola matang (grace-frames `hold_frames`,
  `max_jump`, `smooth_factor`/`smooth_rot`, warna per ID, `model_scenes`) —
  salin pola itu bila scene barumu butuh stabilisasi/multi-model.

---

## 6. Troubleshooting

| Gejala | Penyebab umum | Perbaikan |
|---|---|---|
| `Invalid get index 'AR'` | Autoload belum didaftarkan | Ulangi bagian 1, pastikan Enabled |
| Layar hitam, tanpa log `[AR]` | `AR.start()` gagal / `.so` lama | Cek `res://bin/gd_opencv.gdns` ada, rebuild `.so`, restart editor |
| `PEMROSESAN NONAKTIF` | `show_processed=false` | `AR.set_show_processed(true)` |
| Kubus meleset dari marker | FOV kamera beda dgn fx OpenCV | Pakai rumus bagian 3 (~45° utk 640x480) |
| Kubus kedip | Deteksi kedip (glare layar HP) | Tiru grace-frames `MainAR.gd` (`hold_frames=12`) |
| 2 kamera terbuka | Worker lama + autoload jalan bersamaan | Hapus salah satunya (bagian 5) |

(Lanjut ke bagian 2: scene 2D, migrasi, troubleshooting.)
