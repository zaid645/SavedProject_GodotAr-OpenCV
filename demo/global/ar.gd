extends Node
class_name ARSession
# AR — NODE (bukan autoload): tambahkan sendiri ke scene yang butuh AR.
# Aturan lokal proyek: script yg memakai extends_node WAJIB class_name agar
# bisa dibuat lewat add_child(). Lihat IMPLEMENTATION_AR.MD.
#
# Cukup taruh 1 node ARSession di scene (atau instansiasi dari kode via
# ARSession.new()). Node ARSpawner terpisah akan mencari node ini otomatis.
#
# Arsitektur: GDNative worker (gd_opencv.gdns) -> ARSession -> scene/ARSpawner.
# Fokus utama scene 3D; scene 2D bisa pakai sinyal frame_updated yang sama.

signal frame_updated(image)
signal marker_detected(ids, translations, rotations)
signal marker_lost
signal status_changed(text)

const GDNS_PATH := "res://bin/gd_opencv.gdns"

# Konfigurasi — samakan dgn kebutuhan scene (cm: marker 5 cm = 0.05).
export var camera_id: int = 0
export var capture_width: int = 640
export var capture_height: int = 480
export var show_processed: bool = true
export var marker_length: float = 0.05
# Koreksi skala pose: kalikan hasil pose dgn nilai ini (1.0 = tanpa koreksi).
# Pakai bila kubus meleset/menjauh dari marker. Lihat cara kalibrasi di
# IMPLEMENTATION_AR.MD bagian "Kalibrasi cepat pose_scale".
export var pose_scale: float = 1.0
export var auto_start: bool = true  # kamera nyala saat masuk scene
export var auto_create_camera: bool = true  # buat Camera sendiri bila scene tak punya
export var video_enabled: bool = true  # gambar frame kamera sebagai background 3D
export var video_distance: float = 1.0  # jarak quad video di depan kamera (meter)
export var status_label_path: NodePath  # opsional; kosong = status hanya via sinyal

# Cache hasil frame terakhir (siap dibaca kapan pun via getter).
var last_ids: Array = []
var last_translations: Array = []
var last_rotations: Array = []
var last_seen_msec: int = 0

var _worker: Node = null  # GDOpenCVExample (Sprite) buatan C++
var _was_empty: bool = true
var _video_tex: ImageTexture
var _camera: Camera
var _video_quad: MeshInstance


func _ready() -> void:
	_video_tex = ImageTexture.new()
	_ensure_camera()
	if auto_start:
		start()


# --- Node pendukung AR (dibuat sendiri, tidak perlu setup manual) ----------
func _ensure_camera() -> void:
	_camera = _find_camera()
	if _camera == null and auto_create_camera:
		_camera = Camera.new()
		_camera.name = "ARCamera"
		add_child(_camera)
	if _camera == null:
		push_warning("[ARSession] Kamera tidak ditemukan dan auto_create_camera dinonaktifkan.")
		return
	_camera.current = true
	_sync_camera_fov()


func _find_camera() -> Camera:
	var root := get_tree().current_scene
	if root == null:
		return null
	return _find_camera_recursive(root)


func _find_camera_recursive(n: Node) -> Camera:
	if n is Camera:
		return n as Camera
	for c in n.get_children():
		var found := _find_camera_recursive(c)
		if found != null:
			return found
	return null


# Samakan FOV kamera dgn fx OpenCV agar objek pas di atas marker pada video.
# fx efektif = 0.9*width*pose_scale (pose_scale mengoreksi kesalahan skala
# intrinsik/marker). Tanpa ini pose benar tapi terlihat meleset.
func _sync_camera_fov() -> void:
	if _camera == null or capture_width <= 0 or capture_height <= 0:
		return
	var fx := 0.9 * float(capture_width) * max(pose_scale, 0.0001)
	_camera.fov = rad2deg(2.0 * atan(float(capture_height) / (2.0 * fx)))


func set_pose_scale(v: float) -> void:
	if v <= 0.0:
		return
	pose_scale = v
	_sync_camera_fov()


# Kenapa quad, bukan TextureRect fullscreen: elemen Control selalu digambar DI
# ATAS 3D dalam satu viewport sehingga menutupi objek. Quad punya depth benar.
# Di scene 2D node 3D ini tidak ter-render (tidak mengganggu).
func _ensure_video_quad() -> void:
	if _camera == null:
		return
	if _video_quad != null and is_instance_valid(_video_quad):
		return
	var half_h := video_distance * tan(deg2rad(_camera.fov * 0.5))
	var half_w := half_h * (float(capture_width) / float(max(capture_height, 1)))
	var quad := QuadMesh.new()
	quad.size = Vector2(half_w * 2.0, half_h * 2.0)
	var mat := SpatialMaterial.new()
	mat.flags_unshaded = true
	mat.albedo_texture = _video_tex
	mat.emission_enabled = true
	mat.emission = Color(1, 1, 1)
	mat.emission_texture = _video_tex
	var mi := MeshInstance.new()
	mi.name = "VideoQuad"
	mi.mesh = quad
	mi.set_surface_material(0, mat)
	_camera.add_child(mi)
	mi.translation = Vector3(0, 0, -video_distance)
	_video_quad = mi


func get_camera() -> Camera:
	return _camera


func get_video_quad() -> MeshInstance:
	return _video_quad


# --- Kontrol kamera -------------------------------------------------------
func start() -> bool:
	if _worker != null and is_instance_valid(_worker):
		return true
	if not ResourceLoader.exists(GDNS_PATH):
		_set_status("GDNative tidak ketemu: " + GDNS_PATH)
		return false
	var resource = load(GDNS_PATH)
	if resource == null or not (resource is NativeScript):
		_set_status("Resource GDNative gagal dimuat atau bukan NativeScript: " + GDNS_PATH)
		return false

	var gdns: NativeScript = resource as NativeScript
	_worker = gdns.new()
	if _worker == null:
		_set_status("Gagal membuat instance worker GDNative.")
		return false

	_worker.name = "ARWorker"
	_apply_config()
	add_child(_worker)
	if not _worker.has_signal("frame_updated") or not _worker.has_signal("marker_detected"):
		_worker.queue_free()
		_worker = null
		_set_status("Worker GDNative tidak menyediakan sinyal frame_updated/marker_detected.")
		return false

	var frame_err = _worker.connect("frame_updated", self, "_on_worker_frame")
	var marker_err = _worker.connect("marker_detected", self, "_on_worker_markers")
	if frame_err != OK or marker_err != OK:
		_worker.queue_free()
		_worker = null
		_set_status("Gagal menghubungkan sinyal worker GDNative.")
		return false

	_set_status("AR aktif. Menunggu marker DICT_4X4_50...")
	return true


func stop() -> void:
	if _worker != null and is_instance_valid(_worker):
		_worker.queue_free()
	_worker = null
	last_ids = []
	last_translations = []
	last_rotations = []
	emit_signal("marker_lost")
	_set_status("AR berhenti.")


func is_running() -> bool:
	return _worker != null and is_instance_valid(_worker)


func set_camera_id(cam_id: int) -> void:
	camera_id = cam_id
	if is_running():
		_worker.set("camera_id", cam_id)


func set_show_processed(v: bool) -> void:
	show_processed = v
	if is_running():
		_worker.set("show_processed", v)


func set_marker_length(meters: float) -> void:
	if meters <= 0.0:
		return
	marker_length = meters
	if is_running() and _worker.has_method("set_marker_length"):
		_worker.call("set_marker_length", meters)


func _apply_config() -> void:
	_worker.set("camera_id", camera_id)
	_worker.set("width", capture_width)
	_worker.set("height", capture_height)
	_worker.set("show_processed", show_processed)
	if _worker.has_method("set_marker_length"):
		_worker.call("set_marker_length", marker_length)
	_worker.visible = false


# --- Sinyal dari worker -> cache + re-emit --------------------------------
func _on_worker_frame(_node, image) -> void:
	if image != null:
		_video_tex.create_from_image(image)
		if video_enabled:
			_ensure_video_quad()
	emit_signal("frame_updated", image)


func _on_worker_markers(_node, ids: Array, translations: Array, rotations: Array) -> void:
	# Koreksi skala pose SEKALI di sumber: semua consumer (spawner, skrip scene)
	# menerima pose yang sudah terkoreksi, plus FOV kamera ikut menyesuaikan.
	var corrected: Array = []
	if pose_scale != 1.0:
		for t in translations:
			var v: Vector3 = t
			corrected.append(v * pose_scale)
	else:
		corrected = translations

	last_ids = ids
	last_translations = corrected
	last_rotations = rotations
	if not ids.empty():
		_was_empty = false
		last_seen_msec = OS.get_ticks_msec()
		emit_signal("marker_detected", ids, corrected, rotations)
	else:
		if not _was_empty:
			_was_empty = true
			emit_signal("marker_lost")
		else:
			# Tetap teruskan array kosong tiap frame agar consumer bisa
			# hitung grace-frames sendiri (pola MainAR.gd).
			emit_signal("marker_detected", ids, corrected, rotations)


# --- Query siap pakai ------------------------------------------------------
func get_video_texture() -> ImageTexture:
	return _video_tex


func has_marker(id: int = -1) -> bool:
	if last_ids.empty():
		return false
	if id < 0:
		return true
	return last_ids.has(id)


func get_marker_index(id: int) -> int:
	# Catatan: JANGAN pakai nama `get_index` — itu method bawaan Node di Godot 3
	# (mengembalikan urutan child). Bentrok signature -> error 146 di editor.
	return last_ids.find(id)


func get_marker_position(id: int) -> Vector3:
	var i := get_marker_index(id) if id >= 0 else 0
	if i < 0 or i >= last_translations.size():
		return Vector3.ZERO
	var t: Vector3 = last_translations[i]
	return Vector3(t.x, -t.y, -t.z)  # OpenCV (Y bawah) -> Godot (Y atas)


func get_marker_basis(id: int) -> Basis:
	var i := get_marker_index(id) if id >= 0 else 0
	if i < 0 or i >= last_rotations.size():
		return Basis()
	return basis_from_rvec(last_rotations[i])


func get_marker_tilt_deg(id: int) -> float:
	var b := get_marker_basis(id)
	return rad2deg(acos(clamp(b.z.dot(Vector3(0, 0, 1)), -1.0, 1.0)))


# Jarak kamera -> marker (meter), sudah termasuk koreksi pose_scale.
# Dipakai untuk kalibrasi: bandingkan dgn jarak pengukuran nyata.
func get_marker_distance(id: int) -> float:
	return get_marker_position(id).length()


static func basis_from_rvec(r: Vector3) -> Basis:
	# rvec = axis * angle (radian, koordinat OpenCV).
	var angle := r.length()
	if angle < 0.0001:
		return Basis()
	var axis: Vector3 = r / angle
	return Basis(Vector3(axis.x, -axis.y, -axis.z), angle)


func status_text() -> String:
	if last_ids.empty():
		return "Menunggu marker DICT_4X4_50..."
	return "ID %s | %.2f m | miring %d°" % [
		str(last_ids),
		get_marker_distance(-1),
		int(round(get_marker_tilt_deg(-1)))
	]


func _set_status(text: String) -> void:
	# Status selalu lewat sinyal; label opsional (kosong = tetap jalan).
	emit_signal("status_changed", text)
	if status_label_path != NodePath(""):
		var lbl := get_node_or_null(status_label_path)
		if lbl != null and lbl is Label:
			lbl.text = text
