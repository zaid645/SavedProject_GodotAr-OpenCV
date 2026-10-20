extends Node
class_name ARImageSession
# ARImageSession — pengganti ARSession khusus jalur IMAGE.
# ArUco (ar.gd) TIDAK disentuh. Sinyal meniru ArUco:
# marker_detected(ids,..) -> image_detected(names,..)
# Fase A: STUB tanpa deteksi. Fase B3: pakai GDImageDetector bila ada.

signal frame_updated(image)
signal image_detected(names, translations, rotations)
signal image_lost
signal status_changed(text)

const GDNS_IMAGE_PATH := "res://bin/gd_image_detector.gdns"

export var camera_id: int = 0
export var capture_width: int = 640
export var capture_height: int = 480
export var show_processed: bool = true
export var auto_start: bool = false
export var auto_create_camera: bool = true
export var video_enabled: bool = true
export var video_distance: float = 1.0
export var status_label_path: NodePath
export var pose_scale: float = 1.0
export var target_width_m: float = 0.20
export var detect_every_n_frames: int = 2
export var min_inliers: int = 20
export var match_ratio: float = 0.75

var last_names: Array = []
var last_translations: Array = []
var last_rotations: Array = []
var last_seen_msec: int = 0

var _worker: Node = null
var _was_empty: bool = true
var _video_tex: ImageTexture
var _camera: Camera
var _video_quad: MeshInstance
var _library: ARImageLibrary


func _ready() -> void:
	_video_tex = ImageTexture.new()
	_ensure_camera()
	if auto_start:
		start()


func _ensure_camera() -> void:
	_camera = _find_camera()
	if _camera == null and auto_create_camera:
		_camera = Camera.new()
		_camera.name = "ARImageCamera"
		add_child(_camera)
	if _camera == null:
		push_warning("[ARImageSession] Kamera tidak ada dan auto_create_camera off.")
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
	mi.name = "VideoQuadImage"
	mi.mesh = quad
	mi.set_surface_material(0, mat)
	_camera.add_child(mi)
	mi.translation = Vector3(0, 0, -video_distance)
	_video_quad = mi


func get_camera() -> Camera:
	return _camera


func is_running() -> bool:
	return _worker != null and is_instance_valid(_worker)


func has_image_backend() -> bool:
	return ResourceLoader.exists(GDNS_IMAGE_PATH)
func start() -> bool:
	if is_running():
		return true
	if not ResourceLoader.exists(GDNS_IMAGE_PATH):
		_set_status("[IMG-STUB] Backend image belum ada (Fase B). Library/spawner tetap bisa diuji.")
		return true
	var resource = load(GDNS_IMAGE_PATH)
	if resource == null or not (resource is NativeScript):
		_set_status("Resource image gagal dimuat: " + GDNS_IMAGE_PATH)
		return false
	_worker = (resource as NativeScript).new()
	if _worker == null:
		_set_status("Gagal membuat worker GDImageDetector.")
		return false
	_worker.name = "ARImageWorker"
	_apply_config()
	add_child(_worker)
	if not _worker.has_signal("frame_updated") or not _worker.has_signal("image_detected"):
		_worker.queue_free()
		_worker = null
		_set_status("Worker image tak sediakan sinyal frame_updated/image_detected.")
		return false
	_worker.connect("frame_updated", self, "_on_worker_frame")
	_worker.connect("image_detected", self, "_on_worker_images")
	_load_db_to_worker()
	_set_status("AR image aktif. Menunggu target...")
	return true


func stop() -> void:
	if is_running():
		_worker.queue_free()
		_worker = null
	last_names = []
	last_translations = []
	last_rotations = []
	emit_signal("image_lost")
	_set_status("AR image berhenti.")


func _apply_config() -> void:
	if _worker == null:
		return
	_worker.set("camera_id", camera_id)
	_worker.set("width", capture_width)
	_worker.set("height", capture_height)
	_worker.set("show_processed", show_processed)
	if _worker.has_method("set_detect_every_n_frames"):
		_worker.call("set_detect_every_n_frames", detect_every_n_frames)
	if _worker.has_method("set_min_inliers"):
		_worker.call("set_min_inliers", min_inliers)
	if _worker.has_method("set_match_ratio"):
		_worker.call("set_match_ratio", match_ratio)
	_worker.visible = false


func set_library(lib: ARImageLibrary) -> void:
	_library = lib
	if is_running():
		_load_db_to_worker()


func _load_db_to_worker() -> void:
	if _worker == null or not _worker.has_method("load_target"):
		return
	var lib := _library
	if lib == null or not is_instance_valid(lib):
		lib = _find_library()
	if lib == null:
		return
	_library = lib
	if _worker.has_method("clear_db"):
		_worker.call("clear_db")
	for e in lib.list_targets():
		if e is Dictionary:
			_worker.call("load_target", str(e.get("image_path", "")), str(e.get("name", "")), float(e.get("width_m", target_width_m)))


func _find_library() -> ARImageLibrary:
	var root := get_tree().current_scene
	if root == null:
		return null
	return _find_library_recursive(root)


func _find_library_recursive(n: Node) -> ARImageLibrary:
	if n is ARImageLibrary:
		return n as ARImageLibrary
	for c in n.get_children():
		var f := _find_library_recursive(c)
		if f != null:
			return f
	return null


func _on_worker_frame(_node, image) -> void:
	if image != null:
		_video_tex.create_from_image(image)
		if video_enabled:
			_ensure_video_quad()
	emit_signal("frame_updated", image)


func _on_worker_images(_node, names: Array, translations: Array, rotations: Array) -> void:
	var corrected: Array = []
	if pose_scale != 1.0:
		for t in translations:
			var v: Vector3 = t
			corrected.append(v * pose_scale)
	else:
		corrected = translations
	last_names = names
	last_translations = corrected
	last_rotations = rotations
	if not names.empty():
		_was_empty = false
		last_seen_msec = OS.get_ticks_msec()
		emit_signal("image_detected", names, corrected, rotations)
	else:
		if not _was_empty:
			_was_empty = true
			emit_signal("image_lost")
		else:
			emit_signal("image_detected", names, corrected, rotations)


func has_target(name: String = "") -> bool:
	if last_names.empty():
		return false
	if name == "":
		return true
	return last_names.has(name)


func get_target_index(name: String) -> int:
	return last_names.find(name)


func get_target_position(name: String) -> Vector3:
	var i := get_target_index(name) if name != "" else 0
	if i < 0 or i >= last_translations.size():
		return Vector3.ZERO
	var t: Vector3 = last_translations[i]
	return Vector3(t.x, -t.y, -t.z)


func get_target_basis(name: String) -> Basis:
	var i := get_target_index(name) if name != "" else 0
	if i < 0 or i >= last_rotations.size():
		return Basis()
	return basis_from_rvec(last_rotations[i])


func get_target_distance(name: String) -> float:
	return get_target_position(name).length()


static func basis_from_rvec(r: Vector3) -> Basis:
	var angle := r.length()
	if angle < 0.0001:
		return Basis()
	var axis: Vector3 = r / angle
	return Basis(Vector3(axis.x, -axis.y, -axis.z), angle)


func status_text() -> String:
	if not is_running() and not has_image_backend():
		return "[IMG-STUB] Menunggu backend Fase B..."
	if last_names.empty():
		return "Menunggu image target..."
	return "IMG %s | %.2f m" % [str(last_names), get_target_distance(str(last_names[0]))]


func _set_status(text: String) -> void:
	emit_signal("status_changed", text)
	if status_label_path != NodePath(""):
		var lbl := get_node_or_null(status_label_path)
		if lbl != null and lbl is Label:
			lbl.text = text


func debug_inject(names: Array, translations: Array, rotations: Array) -> void:
	_on_worker_images(self, names, translations, rotations)

