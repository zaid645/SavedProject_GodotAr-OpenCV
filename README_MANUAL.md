# README MANUAL — Setup Ulang Setelah Clone (Private Repo)

Panduan ini untuk perangkat lain yang baru meng-clone repo private ini.
Karena `.gitignore` mengecualikan file build & file lokal editor, beberapa
langkah WAJIB diulang manual di tiap perangkat. Ikuti berurutan.

> Berlaku untuk: **Godot 3.x** (repo ini GDNative `.gdns` — pola Godot 3.5/3.6),
> **Linux 64-bit**, **OpenCV 4.x + modul aruco**, **SCons**, **g++ C++17**.

---

## 0. Yang ikut / tidak ikut dari git (akibat `.gitignore`)

| Ikut di-clone (ada) | TIDAK ikut (dibangun ulang lokal) |
|---|---|
| `src/*.cpp`, `src/*.h` | `demo/bin/x11/*.so` (hasil build utama) |
| `demo/*.gd`, `demo/*.tscn` (+ `Main3D.tscn` bila sudah kamu buat & commit) | `*.os`, `*.o`, `.scons*` (artefak build) |
| `demo/bin/*.gdns`, `demo/bin/*.gdnlib` | `godot-cpp/bin/*.a` (binding terkompilasi) |
| `SConstruct`, `misc/set_opencv4.sh`, `*.md` | `.godot/`, `*.import` (cache editor lokal) |
| `godot-cpp/` sebagai **submodule** (referensi, isinya ditarik terpisah) | `*.log`, file sementara OS |

Implikasi: di perangkat baru kamu harus (1) tarik submodule,
(2) install dependensi, (3) build `godot-cpp`, (4) build `.so` utama,
(5) buka proyek di editor agar `.godot/` & `*.import` dibuat ulang.

---

## 1. Prasyarat sistem (install sekali per perangkat)

```bash
# Toolchain C++ + build + pkg-config + webcam (V4L2)
sudo apt update
sudo apt install -y build-essential scons pkg-config git \
  libopencv-dev python3-opencv v4l-utils

# Verifikasi:
g++ --version        # butuh C++17
scons --version
pkg-config --modversion opencv4   # harus keluar mis. 4.x.x
ls /usr/include/opencv4/opencv2/aruco.hpp  # modul aruco wajib ada
```

Catatan OpenCV:
- Cara cepat: `libopencv-dev` dari apt (sudah termasuk `aruco`, `calib3d`).
- Bila OpenCV di-build dari source ke path custom, sesuaikan
  `misc/set_opencv4.sh` (contoh: `$HOME/localInstalls/opencv-4.5.2`)
  lalu `source misc/set_opencv4.sh` SEBELUM tiap `scons` / run Godot:
  ```bash
  source misc/set_opencv4.sh
  echo $PKG_CONFIG_PATH   # pastikan mengarah ke install custom
  ```
- Godot: pakai **Godot 3.6.3** (binary `godot` / `godot3`).
  Repo ini TIDAK kompatibel Godot 4 (itu butuh GDExtension, bukan `.gdns`).

---

## 2. Clone repo private + submodule

```bash
# Ganti URL dengan URL repo PRIVATE kamu:
git clone --recursive <URL_REPO_PRIVATE_KAMU>
cd godot-cpp-opencv

# Bila lupa --recursive / folder godot-cpp kosong:
git submodule update --init --recursive
ls godot-cpp/godot-headers/Godot.hpp   # harus ada
cat .gitmodules                        # harus menunjuk branch 3.5
```

---

## 3. Build `godot-cpp` (sekali per perangkat, output-nya di-ignore git)

```bash
cd godot-cpp
scons platform=linux generate_bindings=yes -j$(nproc)
ls -l bin/libgodot-cpp.linux.debug.64.a   # harus ada
cd ..
```

---

## 4. Build library utama `.so` (wajib — file ini di-ignore git)

```bash
# Bila OpenCV custom: source misc/set_opencv4.sh dulu
scons platform=linux -j$(nproc)
ls -l demo/bin/x11/libgdopencvexample.so   # timestamp harus baru
```

Setiap mengubah `src/*.cpp` / `src/*.h`, ulangi langkah ini lalu
restart / reload proyek di editor agar sinyal baru
(`marker_detected`, property `marker_length`) terbaca.

---

## 5. Buka di editor & biarkan Godot membuat file lokal

```bash
# Jalankan dari TERMINAL agar LD_LIBRARY_PATH OpenCV terbawa:
godot --path demo     # bila binary bernama godot3, pakai godot3 --path demo
```

- Saat pertama dibuka, Godot membuat ulang `.godot/` dan `*.import`
  (file-file ini memang di-ignore — JANGAN dicommit).
- Bila muncul error library tidak ketemu: cek `.so` ada (langkah 4) dan
  `demo/bin/gd_opencv.gdnlib` masih menunjuk
  `X11.64="res://bin/x11/libgdopencvexample.so"`.

---

## 6. Scene: apa yang ikut, apa yang harus dibuat

- **Ikut dari git:** `demo/Main2D.tscn` (debug video).
  Setelah langkah 4–5, upgrade manual sekali mengikuti
  `scene_implementation.md` bagian B:
  `show_processed=true`, worker `Visible=OFF`, tambah `StatusLabel`,
  hubungkan `frame_updated` + `marker_detected`.
- **Kemungkinan TIDAK ikut (buatan lokal):** `demo/Main3D.tscn`.
  Bila belum ada di repo, buat manual mengikuti
  `scene_implementation.md` bagian C (root `Main3D` + `MainAR.gd`
  + `Camera` + `Cube` CubeMesh 5 cm + `ARWorker` + `StatusLabel`
  + koneksi `marker_detected`).
- Setelah scene beres dan teruji, commit `*.tscn`/`*.gd` tersebut ke private
  repo agar perangkat berikutnya tinggal pull.

---

## 7. Verifikasi cepat (urut, berhenti di yang gagal)

```bash
scons platform=linux -j$(nproc)
godot --path demo
```

| # | Harapan | Bila gagal |
|---|---|---|
| 1 | Log `[AR] OpenCVProcessing berhasil dibuat.` | `.so` belum dibuild / salah path |
| 2 | Log `[AR] Pemrosesan aktif...` | `show_processed` masih false |
| 3 | Arahkan marker DICT_4X4_50 dari layar HP → `[AR] MARKER TERDETEKSI!` + kotak + sumbu XYZ | Bukan 4x4_50 / glare layar / terlalu kecil |
| 4 | `StatusLabel` → `Marker ID: ...` | Koneksi `marker_detected` belum dibuat |
| 5 | Run `Main3D` → kubus muncul/ikut/hilang | Cek koneksi sinyal + `marker_length=0.05` |

Tips marker-dari-layar: brightness maksimal, matikan night-mode,
perbesar hingga ~1/4 layar, miringkan HP 5–10° hindari pantulan,
dekatkan 50→25 cm perlahan.

---

## 8. Alur commit ke private repo (kamu yang lakukan)

```bash
git status --short        # pastikan .so/.os/.godot TIDAK muncul (ter-ignore)
git add .gitignore demo/MainAR.gd demo/Main2D.gd demo/Main3D.tscn \
  src/ scene_implementation.md README_MANUAL.md plan_implementation.md
git commit -m "AR ArUco: pose + marker_detected + CubeMesh"
git push origin main
```

Jangan commit: `demo/bin/x11/*.so`, `*.os`, `godot-cpp/bin/`,
`.godot/`, `*.import`, `*.log`.
