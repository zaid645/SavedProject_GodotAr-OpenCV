# Instruksi Scene — Upgrade Image Target (dikerjakan manusia di editor)

> File `.tscn` TIDAK dibuat via kode — file `.tscn` hasil generate terbukti tidak bisa
> dibuka di editor (percobaan sebelumnya). Semua scene di bawah dibuat MANUAL oleh
> manusia di editor Godot mengikuti struktur node di tiap bagian.
> File `.gd` (node/session/spawner/library) BOLEH dibuat via kode.
> Acuan rencana: `plan_implementation_upgrade.md` (§4 kontrak node, §5 format data, §7 kontrak scene).
> Alur RILIS (dev-time bundle): INPUT laptop → SIMPAN user:// → PASANG scene →
> EXPORT res://targets/ → SCAN OUTPUT → APK. Lihat `implementation_add-ar.md`.
> Klien tidak input apa pun. Scene S1/S2 = DEV TOOL (exclude dari preset export rilis).

---

## 0. Konsep bundle (baca dulu)

```
S1-ScanInput ─▶ user://targets/ (dev-work sementara)
S2-Library ───▶ konektor nama → res://models/X.tscn
Export ───────▶ res://targets/manifest.json + .png (ikut APK, read-only)
S3-ScanOutput ▶ baca bundle ▶ match ORB ▶ instance scene ▶ tempel
```

`ARImageLibrary.list_targets()` menggabung bundle + dev-work (dev-work menang bila
nama sama). `remove_target`/`update_scene` menolak ubah bundle (proteksi benar).
S3 rilis HANYA membaca bundle — `user://` kosong di install baru adalah normal.

---

## Catatan umum (berlaku semua scene)

- Godot 3.x. Main scene aktif diganti via Project Settings → Application → Run → Main Scene.
- Satu kamera aktif per scene (jangan `auto_start` ARSession + ARImageSession bersamaan).
- Class baru (`ARImageSession`, `ARImageLibrary`, `ARImageSpawner`) muncul di
  Create Node setelah `.gd` punya `class_name` + editor di-reload.
- `user://targets/` dibuat otomatis oleh `ARImageLibrary` saat pertama save.

---

## 1. S1 — ScanInput.tscn (DEV TOOL: daftar target)

Scene Control BARU, save sebagai `demo/ScanInput.tscn`. Struktur node:

```
ScanInput (Control, attach skrip inline baru scan_input.gd)
+-- Preview (TextureRect, expand)
+-- TargetName (LineEdit, placeholder "nama_target")
+-- WidthCm (SpinBox, min 1 max 200 value 20)
+-- BtnFile (Button "Pilih File...")
+-- BtnSave (Button "Simpan Target")
+-- BtnExport (Button "Export ke Bundle")   # <-- BARU: export_to_bundle()
+-- StatusLabel (Label)
+-- FileDialog (FileDialog, filter *.png;*.jpg;*.jpeg)
+-- ARImageLibrary (Node, class ARImageLibrary)
```

Logika `scan_input.gd` (tulis manual di editor, pola):

```gdscript
extends Control
var _img: Image = null
func _on_BtnFile_pressed(): $FileDialog.popup_centered()
func _on_FileDialog_file_selected(path):
	_img = Image.new(); _img.load(path)
	var t := ImageTexture.new(); t.create_from_image(_img)
	($Preview as TextureRect).texture = t
func _on_BtnSave_pressed():
	var lib := $ARImageLibrary as ARImageLibrary
	var w_m := float($WidthCm.value) / 100.0
	var err := lib.add_target(_img, $TargetName.text, w_m)
	$StatusLabel.text = "OK tersimpan." if err == "" else err
func _on_BtnExport_pressed():
	var lib := $ARImageLibrary as ARImageLibrary
	var err := lib.export_to_bundle()
	$StatusLabel.text = "Export OK → res://targets/." if err == "" else err
```

Catatan: tampilkan pesan DITOLAK dari `add_target()` apa adanya
(itu pesan "terlalu polos → ganti gambar"). Wajib cetak kertas 15–20 cm,
bukan layar HP. Exclude dari preset export rilis.


## 2. S2 — Library.tscn (DEV TOOL: konektor nama → scene model)

Scene Control BARU `demo/Library.tscn`:

```
Library (Control, attach library_view.gd)
+-- Grid (GridContainer, columns 2)
+-- BtnExport (Button "Export ke Bundle")   # <-- BARU
+-- StatusLabel (Label)
+-- SceneDialog (FileDialog, filter *.tscn, akses res://models/)
+-- ARImageLibrary (Node, class ARImageLibrary)
```

`library_view.gd` pola: `_ready` connect `library_changed` → `_refresh()`;
`_refresh()` hapus anak Grid, untuk tiap `lib.list_targets()` buat baris
thumbnail (`TextureRect` load `image_path`) + `Label "nama (kp, W cm) → scene"`.
Badge `[BUNDLE]` bila `bundled=true`. Tombol:
Hapus → `lib.remove_target(nama)` (tampilkan string kembaliannya; bundle ditolak);
Scene → popup SceneDialog → `lib.update_scene(nama, path)`;
Export → `lib.export_to_bundle()` → status OK/gagal.
Exclude dari preset export rilis.

## 3. S4 — Wrapper model res://models/*.tscn (MANUAL WAJIB, dari scene lain)

Setiap target butuh SATU wrapper. Langkah di editor (per model):

1. Scene → New Inherited Scene → pilih scene sumber (mis. `KursiAsli.tscn`).
2. Save As → `demo/models/Kursi.tscn`.
3. Syarat konten AR: root `Spatial`; TANPA Camera/WorldEnvironment; skala meter
   (kursi ~0.45 m); origin = titik tumpu (alas di y=0). Lihat detail +
   kegagalan umum di `implementation_add-ar.md` §3.
4. Template pertama: `demo/models/ContohKubus.tscn` — kubus 10 cm
   (root Spatial + child MeshInstance CubeMesh 0.1 + SpatialMaterial emission),
   dibuat manual sebagai acuan; konektor contoh: `contoh_poster → ContohKubus.tscn`.

## 4. S3 — ScanOutput.tscn (RUNTIME/RILIS: kamera + spawn dari bundle)

Scene Spatial BARU `demo/ScanOutput.tscn` (Main Scene rilis):

```
ScanOutput (Spatial)
+-- ARImageCamera (Camera, current)
+-- ARImageLibrary (Node, class ARImageLibrary)   # otomatis baca bundle
+-- ARImageSession (Node, class ARImageSession,
|    auto_start=true, detect_every_n_frames=2, min_inliers=20,
|    status_label_path=../StatusLabel)
+-- ARImageSpawner (Node, class ARImageSpawner,
|    smooth_factor=6..8, max_jump=0.20, hold_frames=8..10,
|    status_label_path=../StatusLabel)
+-- StatusLabel (Label)
```

PENTING: TIDAK ada ARSession/ARWorker `auto_start` (satu kamera aktif) dan TIDAK
ada FileDialog/Input di scene ini. `target_map` kosong = diambil dari bundle
(`scene_path` manifest). Run → target kertas cetak → model menempel; hilang >
hold → hide+free. Tuning image (beda ArUco): smooth 6-8, max_jump 0.20, hold 8-10.

## 5. Export APK (preset)

Main Scene = `ScanOutput.tscn`. Export Preset → Filters: exclude `ScanInput.tscn`,
`Library.tscn`; WAJIB sertakan `demo/targets/` + `demo/models/`. Regresi: Main3D
ArUco tetap spawn kubus (`own_opencv_processing.*`, `gd_opencv.*`, `ar.gd`,
`ar_marker_spawner.gd` harus NOL perubahan — cek `git status`).

