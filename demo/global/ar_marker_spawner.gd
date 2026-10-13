extends Spatial
class_name ARMarkerSpawner
# Spawner AR — node TERPISAH dari pemrosesan AR (tidak perlu tahu GDNative).
# Taruh 1x di scene 3D, tentukan sesi AR + tabel marker->scene, selesai.
#
# Cara pakai:
#   1) Tambahkan node ARSession (class_name ARSession, res://global/ar.gd)
#      di scene (Spatial biasa), atau biarkan spawner membuatnya sendiri
#      (auto_create_session = true).
#   2) Tambahkan node ARMarkerSpawner; set `session_node` ke node ARSession
#      (boleh dikosongkan bila auto_create_session / hanya 1 sesi di scene).
#   3) Isi `marker_map` di Inspector:  key = ID ArUco (int),
#                                        value = PackedScene (.tscn objek).
#   4) Run. Marker ID terlihat -> scene-nya di-instance & ditempel di pose
#      marker; hilang > hold_frames -> instance disembunyikan lalu di-free.
#
# Kelebihan node ini vs MainAR.gd: satu scene baru tak perlu tahu apa pun soal
# ArUco/GDNative — cukup pilih scene objek per ID.

signal spawned(id, instance)
signal despawned(id)

export var auto_create_session: bool = true
export var session_node: NodePath  # node ARSession; kosong = cari otomatis
export var marker_map: Dictionary = {}  # {id:int -> PackedScene}
export var smooth_factor: float = 8.0  # lerp posisi
export var smooth_rot: float = 8.0  # slerp rotasi
export var hold_frames: int = 12  # toleransi kedip marker
export var max_jump: float = 0.15  # meter; tolak lompatan pose (0 = mati)
export var marker_length: float = 0.05  # meter; untuk fallback kubus
export var fallback_cube: bool = true  # ID tak ada di marker_map -> kubus warna unik
export var status_label_path: NodePath  # Label (opsional) utk status teks

var _session: ARSession
var _instances := {}  # id -> Spatial
var _missed := {}
var _spawned := {}


func _ready() -> void:
	_find_or_create_session()
	if _session == null:
		push_warning("[ARSpawner] Tidak ada ARSession di scene. Set `auto_create_session` atau taruh node ARSession.")
		return
	_session.connect("marker_detected", self, "_on_markers")
	_session.connect("status_changed", self, "_on_status")
	if not _session.is_running():
		_session.start()
	_set_status("Menunggu marker DICT_4X4_50...")


func _find_or_create_session() -> void:
	if session_node != NodePath(""):
		var n := get_node_or_null(session_node)
		if n is ARSession:
			_session = n
			return
		push_warning("[ARSpawner] `session_node` bukan ARSession, cari otomatis.")
	# Cari sesi yg sudah ada di scene.
	var existing := _find_session_recursive(get_tree().current_scene)
	if existing != null:
		_session = existing
		return
	if auto_create_session:
		_session = ARSession.new()
		_session.name = "ARSession"
		add_child(_session)



func _find_session_recursive(n: Node) -> ARSession:
	if n is ARSession:
		return n as ARSession
	for c in n.get_children():
		var f: ARSession = _find_session_recursive(c)
		if f != null:
			return f
	return null



func _on_markers(_node, ids: Array, translations: Array, rotations: Array) -> void:
	if ids.empty():
		_tick_missed({})
		return
	var seen := {}
	for i in range(ids.size()):
		var id := int(ids[i])
		if i >= translations.size() or i >= rotations.size():
			continue
		seen[id] = true
		_missed[id] = 0
		var t: Vector3 = translations[i]
		var pos := Vector3(t.x, -t.y, -t.z)  # OpenCV -> Godot
		var basis := ARSession.basis_from_rvec(rotations[i])
		var node: Spatial = _ensure_instance(id)
		if node == null:
			continue
		if not _spawned.get(id, false):
			node.transform = Transform(basis, pos)
			node.visible = true
			_spawned[id] = true
			emit_signal("spawned", id, node)
		else:
			if max_jump > 0.0 and node.translation.distance_to(pos) > max_jump:
				pos = node.translation
			var wp: float = clamp(smooth_factor * get_process_delta_time(), 0.0, 1.0)
			var wr: float = clamp(smooth_rot * get_process_delta_time(), 0.0, 1.0)
			var b: Basis = node.transform.basis.slerp(basis, wr)
			var p: Vector3 = node.translation.linear_interpolate(pos, wp)
			node.transform = Transform(b, p)
			node.visible = true
	_tick_missed(seen)


func _ensure_instance(id: int) -> Spatial:
	if _instances.has(id):
		return _instances[id] as Spatial
	var node: Spatial = null
	if marker_map.has(id) and marker_map[id] is PackedScene:
		var inst: Node = (marker_map[id] as PackedScene).instance()
		if inst is Spatial:
			node = inst
	if node == null and fallback_cube:
		node = _make_cube(id)
	if node == null:
		return null
	add_child(node)
	node.visible = false
	_instances[id] = node
	return node


func _make_cube(id: int) -> MeshInstance:
	var mi := MeshInstance.new()
	var box := CubeMesh.new()
	box.size = Vector3(marker_length, marker_length, marker_length)
	mi.mesh = box
	var mat := SpatialMaterial.new()
	var c := Color.from_hsv(fmod(float(abs(id)) * 0.37 + 0.08, 1.0), 0.85, 1.0)
	mat.albedo_color = c
	mat.emission_enabled = true
	mat.emission = c
	mi.set_surface_material(0, mat)
	return mi


func _tick_missed(seen: Dictionary) -> void:
	for id in _instances.keys():
		if seen.has(id):
			continue
		_missed[id] = int(_missed.get(id, 0)) + 1
		if _missed[id] > hold_frames:
			var n := _instances[id] as Spatial
			n.visible = false
			emit_signal("despawned", id)
			n.queue_free()
			_instances.erase(id)
			_spawned.erase(id)
			_missed.erase(id)
	if _instances.empty() or _all_hidden():
		_set_status("Menunggu marker DICT_4X4_50...")


func _all_hidden() -> bool:
	for id in _instances.keys():
		if (_instances[id] as Spatial).visible:
			return false
	return true


func _on_status(text: String) -> void:
	_set_status(text)


func _set_status(text: String) -> void:
	if status_label_path != NodePath(""):
		var lbl := get_node_or_null(status_label_path)
		if lbl != null and "text" in lbl:
			lbl.text = text


# --- API pemetaan (agar tak perlu edit Dictionary manual di Inspector) -----
# marker_map tetap export var per-node: tiap scene/instance punya isi sendiri.
# Tambah dari kode bila scene AR baru butuh pasangan ID->scene berbeda.
func add_marker(id: int, scene: PackedScene) -> void:
	if scene != null:
		marker_map[id] = scene


func clear_markers() -> void:
	marker_map.clear()


func marker_ids() -> Array:
	return marker_map.keys()
