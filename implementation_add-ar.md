# Menambah Gambar + Model 3D Baru (Developer, Dev-time Bundle)

> Alur: INPUT (laptop) → SIMPAN (user://) → PASANG SCENE → EXPORT (res://) → SCAN OUTPUT → APK.
> Klien TIDAK input apa pun. Semua langkah di bawah dilakukan developer di laptop.
> Aturan repo: `.tscn` HANYA manual di editor. `.gd`/`.json` boleh via kode.
> Acuan: `plan_implementation_upgrade.md` (§4–§5), `plan_implementation_upgrade-scene.md` (§1–§4).

## 0. Konsep (baca dulu, 1 menit)

```
S1-ScanInput ──add_target()──▶ user://targets/ (dev-work, sementara)
S2-Library ──update_scene()──▶ pasang konektor nama → res://models/X.tscn
Tombol Export ─export_to_bundle()─▶ res://targets/manifest.json + .png (ikut APK)
S3-ScanOutput ─▶ baca bundle ▶ ORB match ▶ instance scene ▶ tempel di pose
```

Konektor gambar→model = SATU baris mapping: `nama_target → scene_path`.
Contoh: `poster_kopi → res://models/Kursi.tscn`. Tidak ada node konektor khusus.

## 1. Siapkan gambar target (ceklist sebelum input)

- [ ] Gambar bertekstur kaya, kontras tersebar (poster/cover/foto ramai). TOLAK: gradasi
      polos, logo 2 warna, teks kecil saja.
- [ ] Cetak KERTAS ukuran 15–20 cm lebar (A5–A4). Jangan uji dari layar HP (glare/moire).
- [ ] Ukur lebar fisik pakai penggaris → catat dalam cm (mis. 20 cm → `width_m = 0.20`).
- [ ] File master `.png/.jpg` resolusi penuh (preprocess ≤480px dilakukan otomatis).

Rekomendasi: mulai 2–3 target. Ambang lolos `keypoints >= 150`.

## 2. Input gambar (S1-ScanInput, Run di laptop)

1. Buka `demo/ScanInput.tscn` → Run (F5). Main scene lain JANGAN auto_start kamera.
2. Klik Pilih File → pilih gambar master → Preview tampil.
3. Isi Nama (unik, huruf/angka/`_`/`-`, mis. `poster_kopi`) + Lebar cm (hasil ukur).
4. Klik Simpan Target.
   - `OK tersimpan` → lanjut.
   - `DITOLAK: terlalu polos (N keypoint...)` → GANTI gambar (bukan naikkan threshold).
     Gambar polos TIDAK akan bisa di-track ORB — gagal cepat di sini lebih murah
     daripada gagal misterius saat scan.
5. Ulangi untuk tiap target baru.

Hasil tahap ini: `user://targets/<nama>.png` + entri di `user://targets/index.json`.

## 3. Siapkan scene model 3D (MANUAL di editor — tidak bisa via kode)

Setiap target butuh SATU wrapper `.tscn` di `res://models/`. Bila model berasal dari
scene lain yang sudah ada, JANGAN copy-paste node mentah — bungkus sebagai inherited scene:

1. Scene → New Inherited Scene → pilih scene sumber (mis. `KursiAsli.tscn`).
2. Save As → `demo/models/Kursi.tscn`.
3. Periksa syarat konten AR (wajib):
   - [ ] Root adalah `Spatial` (bukan Control/Camera).
   - [ ] TIDAK ada `Camera` / `WorldEnvironment` di dalam (pakai kamera ScanOutput).
   - [ ] Skala meter: mis. kursi tinggi ~0.45 m. Bila model impor `.glb` raksasa,
         kecilkan root `scale` hingga wajar, lalu Bake / terapkan.
   - [ ] Origin = titik tumpu: mis. alas kursi di y=0 agar duduk pas di atas gambar.
4. Ulangi untuk tiap model. Contoh template: `demo/models/ContohKubus.tscn`
   (kubus 10 cm, dibuat manual mengikuti pola yang sama).

Kegagalan umum: root `MeshInstance` tanpa Spatial (rotasi aneh saat slerp),
model 100× skala (menutupi kamera), origin di tengah (setengah tenggelam).

## 4. Pasang konektor (S2-Library, Run di laptop)

1. Buka `demo/Library.tscn` → Run. Grid menampilkan thumbnail + `nama (kp, W cm)`.
2. Untuk tiap target: klik Ganti Scene → FileDialog → pilih `res://models/X.tscn`.
   Status baris berubah menampilkan scene terpasang.
3. Uji cepat (opsional tapi disarankan): Main Scene → `ScanOutput.tscn` → Run →
   arahkan kertas cetak → model menempel + ikut miring. Belum pas? tuning §6.

Hasil tahap ini: `scene_path` terisi di dev-work. Belum ikut APK sampai Export.

## 5. Export ke bundle (wajib sebelum build APK)

1. Di S1 ATAU S2 klik tombol **Export ke Bundle** (`export_to_bundle()`).
2. Cek OK: `demo/targets/manifest.json` bertambah + `demo/targets/<nama>.png` ada.
3. `git add demo/targets demo/models` — bundle ikut commit & ikut APK.
4. ScanOutput saat rilis HANYA membaca bundle (dev-work `user://` diabaikan di APK
   karena tiap install baru `user://` kosong — benar begitu).

Manifest per entri: `{name, image, width_m, keypoints, scene}` (+ alias
`image_path`/`scene_path` untuk kompatibilitas). Contoh ada di
`demo/targets/manifest.json` (`contoh_poster → ContohKubus.tscn`).

## 6. Uji ScanOutput + tuning

Main Scene → `demo/ScanOutput.tscn` → Run → arahkan 2–3 target cetak:

| Gejala | Obat |
|---|---|
| Model goyang | turunkan `smooth_factor` ke 6–8 (jangan naikkan) |
| Meloncat saat gerak cepat | kecilkan `max_jump` ke 0.20 |
| Kedip/hilang sesaat | naikkan `hold_frames` ke 8–10 |
| Tak terdeteksi walau jelas | cek `min_inliers` 20, `detect_every_n_frames` 2, cahaya merata, kertas tidak melengkung |
| Model tenggelam/melayang | perbaiki origin + skala wrapper (§3), kalibrasi `pose_scale` vs penggaris |

## 7. Build APK (klien hanya terima hasil)

1. Project Settings → Main Scene = `demo/ScanOutput.tscn`.
2. Export Preset Android → Filters: exclude `demo/ScanInput.tscn`, `demo/Library.tscn`
   (scene dev tetap di repo, tidak ikut APK). `demo/targets/` + `demo/models/` WAJIB ikut.
3. Install di HP → arahkan ke cetakan kertas → model muncul. Selesai.

## 8. Troubleshooting cepat

- `Nama sudah ada` → nama case-insensitive unik; tambah ulang = timpa dev-work (bundle aman).
- `Target bundle read-only` (saat Hapus/Ubah) → itu proteksi benar; tambah entri
  dev-work nama sama untuk override sementara, Export untuk bekukan.
- `Resource image gagal dimuat` → `demo/bin/gd_image_detector.gdns` belum reload;
  restart editor setelah rebuild `.so`.
- Jalur ArUco ikut rusak → STOP, cek `git status`: file `own_opencv_processing.*`,
  `gd_opencv.cpp/.h`, `ar.gd`, `ar_marker_spawner.gd` harus NOL perubahan.
