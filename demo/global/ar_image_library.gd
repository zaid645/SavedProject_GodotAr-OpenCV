extends Node
class_name ARImageLibrary
# ARImageLibrary — single source of truth untuk natural image target.
# Jalur IMAGE. TIDAK menyentuh jalur ArUco (ar.gd / ar_marker_spawner.gd).
# DUA SUMBER (digabung di list_targets):
#   1) BUNDLE dev: res://targets/manifest.json (+ .png + scene model) — ikut APK,
#      read-only, diisi developer. Lihat implementation_add-ar.md.
#   2) DEV-WORK: user://targets/index.json + .png — ditulis saat Run S1 di laptop,
#      lalu tombol Export menyalinnya ke res://targets/.
# Format entri: {name, image_path, width_m, keypoints, scene_path, bundled}
# Validasi add_target: nama unik+tak kosong, width_m>0, keypoints>=MIN_KEYPOINTS.
# Estimator keypoint Fase A = varians Laplacian sederhana (placeholder);
# diganti hitungan ORB asli dari C++ di Fase B1 (TODO-B1).

signal library_changed

const TARGETS_DIR := "user://targets"
const INDEX_PATH := "user://targets/index.json"
const BUNDLED_DIR := "res://targets"
const BUNDLED_MANIFEST := "res://targets/manifest.json"
const MAX_WIDTH := 480
const MIN_KEYPOINTS := 150

var _targets := {}  # dev-work (user://), name -> Dictionary
var _bundled := {}  # bundle (res://), name -> Dictionary (read-only)


func _ready() -> void:
	load()


func _read_json_array(path: String) -> Array:
	var f := File.new()
	if not f.file_exists(path):
		return []
	if f.open(path, File.READ) != OK:
		push_warning("[ARImageLibrary] Gagal buka " + path)
		return []
	var parsed = JSON.parse(f.get_as_text())
	f.close()
	if parsed.error != OK or not (parsed.result is Dictionary):
		push_warning("[ARImageLibrary] JSON rusak: " + path)
		return []
	return (parsed.result as Dictionary).get("targets", [])


func load() -> void:
	_ensure_dir()
	_targets.clear()
	_bundled.clear()
	for e in _read_json_array(INDEX_PATH):
		if e is Dictionary and (e as Dictionary).has("name"):
			var d: Dictionary = (e as Dictionary).duplicate()
			d["bundled"] = false
			_targets[str(d["name"])] = d
	# Bundle read-only: user menimpa bila nama sama (prioritas dev-work).
	for e in _read_json_array(BUNDLED_MANIFEST):
		if e is Dictionary and (e as Dictionary).has("name"):
			var d: Dictionary = (e as Dictionary).duplicate()
			d["bundled"] = true
			if not _targets.has(str(d["name"])):
				_bundled[str(d["name"])] = d
	emit_signal("library_changed")


func _ensure_dir() -> void:
	var d := Directory.new()
	if not d.dir_exists(TARGETS_DIR):
		d.make_dir_recursive(TARGETS_DIR)


func save() -> void:
	_ensure_dir()
	var arr := []
	var keys := _targets.keys()
	keys.sort()
	for k in keys:
		arr.append(_targets[k])
	var f := File.new()
	if f.open(INDEX_PATH, File.WRITE) != OK:
		push_warning("[ARImageLibrary] Gagal tulis index.json")
		return
	f.store_string(JSON.print({"targets": arr}, "\t"))
	f.close()


# Gabungan bundle + dev-work (dev-work menang bila nama sama).
func list_targets() -> Array:
	var out := []
	var seen := {}
	var keys := _targets.keys()
	keys.sort()
	for k in keys:
		out.append((_targets[k] as Dictionary).duplicate())
		seen[str(k)] = true
	var bk := _bundled.keys()
	bk.sort()
	for k in bk:
		if not seen.has(str(k)):
			out.append((_bundled[k] as Dictionary).duplicate())
	return out


func get_target(name: String) -> Dictionary:
	if _targets.has(name):
		return (_targets[name] as Dictionary).duplicate()
	if _bundled.has(name):
		return (_bundled[name] as Dictionary).duplicate()
	return {}


func has_target(name: String) -> bool:
	return _targets.has(name) or _bundled.has(name)


func is_bundled(name: String) -> bool:
	return _bundled.has(name) and not _targets.has(name)


func add_target(image: Image, name: String, width_m: float, scene_path := "") -> String:
	var clean := name.strip_edges()
	if clean == "":
		return "Nama target kosong."
	for k in _targets.keys():
		if str(k).to_lower() == clean.to_lower():
			return "Nama '%s' sudah ada." % clean
	if width_m <= 0.0:
		return "Lebar fisik harus > 0 (meter)."
	if image == null:
		return "Gambar null."
	# Sanitasi nama file: hanya alnum + _ -
	var fname := ""
	for i in range(clean.length()):
		var ch := clean[i]
		if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == "_" or ch == "-":
			fname += ch
		elif ch == " ":
			fname += "_"
	if fname == "":
		return "Nama harus mengandung huruf/angka."
	# Preprocess: grayscale + downscale <=480 (opsi B wajib, §6).
	var img := image.duplicate() as Image
	if img.get_format() != Image.FORMAT_L8:
		img.convert(Image.FORMAT_L8)
	if img.get_width() > MAX_WIDTH:
		var s := float(MAX_WIDTH) / float(img.get_width())
		img.resize(MAX_WIDTH, max(1, int(round(img.get_height() * s))), Image.INTERPOLATE_BILINEAR)
	# Estimator sementara (TODO-B1: ganti ORB C++ asli).
	var kp := estimate_keypoints(img)
	if kp < MIN_KEYPOINTS:
		return "DITOLAK: terlalu polos (%d keypoint, butuh >= %d). Ganti gambar bertekstur / cetak kertas." % [kp, MIN_KEYPOINTS]
	_ensure_dir()
	var png_path := TARGETS_DIR + "/" + fname + ".png"
	if img.save_png(png_path) != OK:
		return "Gagal simpan PNG."
	_targets[clean] = {
		"name": clean,
		"image_path": png_path,
		"width_m": float(width_m),
		"keypoints": int(kp),
		"scene_path": str(scene_path),
	}
	save()
	emit_signal("library_changed")
	return ""


func update_scene(name: String, scene_path: String) -> String:
	if _targets.has(name):
		(_targets[name] as Dictionary)["scene_path"] = str(scene_path)
		save()
		emit_signal("library_changed")
		return ""
	if _bundled.has(name):
		return "Target bundle read-only — salin dulu ke dev-work (tambah ulang nama sama) untuk ubah scene."
	return "Target '%s' tidak ada." % name


func remove_target(name: String) -> String:
	if _bundled.has(name) and not _targets.has(name):
		return "Target bundle read-only, tidak bisa dihapus dari Library."
	if not _targets.has(name):
		return "Target '%s' tidak ada." % name
	var e: Dictionary = _targets[name]
	_targets.erase(name)
	var d := Directory.new()
	var png: String = str(e.get("image_path", ""))
	if png.begins_with("user://") and png != "" and d.file_exists(png):
		d.remove(png)
	var yml := png.get_basename() + ".yml"
	if png.begins_with("user://") and yml != "" and d.file_exists(yml):
		d.remove(yml)
	save()
	emit_signal("library_changed")
	return ""

# Export dev-work -> bundle res://targets/ (dipanggil tombol S1/S2).
# Menyalin .png + menulis manifest.json. CATATAN: di editor, res:// writable;
# di APK hasil export, res:// read-only (benar — bundle dibekukan saat build).
func export_to_bundle(names: Array = []) -> String:
	var dir := Directory.new()
	if not dir.dir_exists(BUNDLED_DIR):
		if dir.make_dir_recursive(BUNDLED_DIR) != OK:
			return "Gagal buat folder res://targets/."
	var picked := []
	if names.empty():
		for e in list_targets():
			if not bool((e as Dictionary).get("bundled", false)):
				picked.append(e)
	else:
		for n in names:
			var e := get_target(str(n))
			if not e.empty() and not bool(e.get("bundled", false)):
				picked.append(e)
	if picked.empty():
		return "Tidak ada target dev-work untuk di-export."
	var manifest := []
	for e in picked:
		var nm := str(e.get("name", ""))
		var src_png := str(e.get("image_path", ""))
		var dst_png := BUNDLED_DIR + "/" + nm + ".png"
		if src_png != dst_png:
			if dir.copy(src_png, dst_png) != OK:
				return "Gagal salin PNG: " + nm
		manifest.append({
			"name": nm,
			"image": dst_png,
			"image_path": dst_png,
			"width_m": float(e.get("width_m", 0.2)),
			"keypoints": int(e.get("keypoints", 0)),
			"scene": str(e.get("scene_path", "")),
			"scene_path": str(e.get("scene_path", "")),
		})
	manifest.sort_custom(self, "_sort_manifest")
	var f := File.new()
	if f.open(BUNDLED_MANIFEST, File.WRITE) != OK:
		return "Gagal tulis manifest.json."
	f.store_string(JSON.print({"targets": manifest}, "\t"))
	f.close()
	load()
	return ""


func _sort_manifest(a, b) -> bool:
	return str(a.get("name", "")) < str(b.get("name", ""))



# Estimator placeholder Fase A: varians Laplacian pada L8.
# Korelasi kasar dgn jumlah sudut/tekstur; threshold 150 dikalibrasi ulang di B1.
static func estimate_keypoints(img: Image) -> int:
	if img == null or img.get_width() < 8 or img.get_height() < 8:
		return 0
	img.lock()
	var w := img.get_width()
	var h := img.get_height()
	var sw := min(w - 1, 60)
	var sh := min(h - 1, 60)
	var ox := (w - sw) / 2
	var oy := (h - sh) / 2
	var sum := 0.0
	var sum2 := 0.0
	var n := 0
	for y in range(oy + 1, oy + sh - 1):
		for x in range(ox + 1, ox + sw - 1):
			var c: float = img.get_pixel(x, y).r * 255.0
			var lap: float = (img.get_pixel(x - 1, y).r + img.get_pixel(x + 1, y).r + img.get_pixel(x, y - 1).r + img.get_pixel(x, y + 1).r) * 255.0 - 4.0 * c
			sum += lap
			sum2 += lap * lap
			n += 1
	img.unlock()
	if n <= 0:
		return 0
	var mean := sum / float(n)
	var variance := sum2 / float(n) - mean * mean
	# Skala empiris: variance ~ puluhan ribu utk gambar kaya tekstur.
	return int(clamp(variance / 40.0, 0.0, 5000.0))
