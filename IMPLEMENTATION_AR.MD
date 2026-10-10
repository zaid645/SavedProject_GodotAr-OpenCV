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

## 1. Daftarkan autoload (sekali per proyek, manual di editor)

> `project.godot` SENGAJA tidak diubah via kode — lakukan sekali di editor:

1. Godot 3.x → **Project → Project Settings → tab Autoload**.
2. **Path**: `res://global/ar.gd`, **Node Name**: `AR` → **Add** → pastikan
   kolom Enabled tercentang.
3. **OK / Close** → `project.godot` otomatis mendapat bagian `[autoload]`.
4. Restart editor bila perlu. Tes cepat: di scene mana pun,
   `print(AR.is_running())` tidak error "Invalid get index 'AR'".

Konfigurasi default di `ar.gd` (bisa diubah dari Inspector autoload/kode):
`camera_id=0`, `640x480`, `show_processed=true`, `marker_length=0.05`,
`auto_start=true`.

---

## 2. Sinyal & API yang disediakan `AR`

| Sinyal | Argumen | Kapan dipancarkan |
|---|---|---|
| `frame_updated` | `(image: Image)` | Tiap frame kamera (reuse untuk background video) |
| `marker_detected` | `(ids, translations, rotations)` | Tiap frame termasuk kosong (agar consumer bisa grace-frames) |
| `marker_lost` | `()` | Sekali saat transisi terlihat → hilang total |
| `status_changed` | `(text: String)` | Perubahan status internal AR |

Fungsi penting: `AR.start()` / `AR.stop()` / `AR.is_running()`,
`AR.set_camera_id(n)`, `AR.set_marker_length(m)`,
`AR.get_video_texture()`, `AR.has_marker(id)`,
`AR.get_marker_position(id)` (sudah konversi sumbu OpenCV→Godot),
`AR.get_marker_basis(id)`, `AR.get_marker_tilt_deg(id)`,
`AR.status_text()`, `AR.basis_from_rvec(r)` (static).

Aturan ID: `id = -1` = "marker pertama / apa saja";
`id >= 0` = ID ArUco spesifik (untuk multi-model).

---

## 3. Scene 3D minimal (yang disarankan)

Struktur scene baru (contoh `Arena3D.tscn`): root `Spatial` + script sendiri
+ `Camera` + `Label StatusLabel`. **Tidak perlu** node `ARWorker`/`Sprite`/
`webcamView` lagi — kamera dipegang autoload.

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


---

## 4. Scene 2D (debug video saja)

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
