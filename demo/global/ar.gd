extends Node
# AR — autoload pusat kamera + deteksi marker ArUco.
# Daftarkan manual: Project Settings > Autoload > Name "AR" > Path res://global/ar.gd
# (lihat IMPLEMENTATION_AR.MD). Scene baru cukup dengar sinyal AR, tanpa ARWorker sendiri.
#
# Arsitektur: GDNative worker (gd_opencv.gdns) -> AR (re-emit) -> scene mana pun.
# Fokus utama scene 3D; scene 2D bisa pakai sinyal frame_updated yang sama.

signal frame_updated(image)
signal marker_detected(ids, translations, rotations)
signal marker_lost
signal status_changed(text)

const GDNS_PATH := "res://bin/gd_opencv.gdns"

# Konfigurasi — samakan dgn kebutuhan scene (cm: marker 5 cm = 0.05).
var camera_id: int = 0
var capture_width: int = 640
var capture_height: int = 480
var show_processed: bool = true
var marker_length: float = 0.05
var auto_start: bool = true

# Cache hasil frame terakhir (siap dibaca kapan pun via getter).
var last_ids: Array = []
var last_translations: Array = []
var last_rotations: Array = []
var last_seen_msec: int = 0

var _worker: Node = null  # GDOpenCVExample (Sprite) buatan C++
var _was_empty: bool = true
var _video_tex: ImageTexture


func _ready() -> void:
	_video_tex = ImageTexture.new()
	if auto_start:
		start()


# --- Kontrol kamera -------------------------------------------------------
func start() -> bool:
	if _worker != null and is_instance_valid(_worker):
		return true
	if not ResourceLoader.exists(GDNS_PATH):
		_set_status("GDNative tidak ketemu: " + GDNS_PATH)
		return false
	var gdns: NativeScript = load(GDNS_PATH) as NativeScript
	_worker = gdns.new()
	_worker.name = "ARWorker"
	_apply_config()
	add_child(_worker)
	_worker.connect("frame_updated", self, "_on_worker_frame")
	_worker.connect("marker_detected", self, "_on_worker_markers")
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
	emit_signal("frame_updated", image)


func _on_worker_markers(_node, ids: Array, translations: Array, rotations: Array) -> void:
	last_ids = ids
	last_translations = translations
	last_rotations = rotations
	if not ids.empty():
		_was_empty = false
		last_seen_msec = OS.get_ticks_msec()
		emit_signal("marker_detected", ids, translations, rotations)
	else:
		if not _was_empty:
			_was_empty = true
			emit_signal("marker_lost")
		else:
			# Tetap teruskan array kosong tiap frame agar consumer bisa
			# hitung grace-frames sendiri (pola MainAR.gd).
			emit_signal("marker_detected", ids, translations, rotations)


# --- Query siap pakai ------------------------------------------------------
func get_video_texture() -> ImageTexture:
	return _video_tex


func has_marker(id: int = -1) -> bool:
	if last_ids.empty():
		return false
	if id < 0:
		return true
	return last_ids.has(id)


func get_index(id: int) -> int:
	return last_ids.find(id)


func get_marker_position(id: int) -> Vector3:
	var i := get_index(id) if id >= 0 else 0
	if i < 0 or i >= last_translations.size():
		return Vector3.ZERO
	var t: Vector3 = last_translations[i]
	return Vector3(t.x, -t.y, -t.z)  # OpenCV (Y bawah) -> Godot (Y atas)


func get_marker_basis(id: int) -> Basis:
	var i := get_index(id) if id >= 0 else 0
	if i < 0 or i >= last_rotations.size():
		return Basis()
	return basis_from_rvec(last_rotations[i])


func get_marker_tilt_deg(id: int) -> float:
	var b := get_marker_basis(id)
	return rad2deg(acos(clamp(b.z.dot(Vector3(0, 0, 1)), -1.0, 1.0)))


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
	return "ID %s | miring %d°" % [str(last_ids), int(round(get_marker_tilt_deg(-1)))]


func _set_status(text: String) -> void:
	emit_signal("status_changed", text)
