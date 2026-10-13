# Instruksi Scene — Upgrade Image Target (dikerjakan manusia di editor)

> File `.tscn` TIDAK dibuat via kode — file `.tscn` hasil generate terbukti tidak bisa
> dibuka di editor (percobaan sebelumnya). Semua scene di bawah dibuat MANUAL oleh
> manusia di editor Godot mengikuti struktur node di tiap bagian.
> File `.gd` (node/session/spawner/library) BOLEH dibuat via kode.
> Acuan rencana: `plan_implementation_upgrade.md` (§4 kontrak node, §5 format data, §7 kontrak scene).

---

## Catatan umum (berlaku semua scene)

- Godot 3.x. Main scene aktif diganti via Project Settings → Application → Run → Main Scene.
- Satu kamera aktif per scene (jangan `auto_start` ARSession + ARImageSession bersamaan).
- Class baru (`ARImageSession`, `ARImageLibrary`, `ARImageSpawner`) muncul di
  Create Node setelah `.gd` punya `class_name` + editor di-reload.
- `user://targets/` dibuat otomatis oleh `ARImageLibrary` saat pertama save.

---

## 0. Instruksi scene di sini

_(placeholder — detail per scene ScanInput / Library / ScanOutput akan ditulis di bagian
1–3 di bawah setelah `.gd` Fase A selesai agar nama sinyal/export var sesuai kode final.)_

- [ ] S1 — ScanInput.tscn (daftar target: kamera/file → nama + lebar cm → simpan)
- [ ] S2 — Library.tscn (grid thumbnail + edit scene + hapus)
- [ ] S3 — ScanOutput.tscn (kamera + ARImageSession + ARImageSpawner + spawn)
