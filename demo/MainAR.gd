extends Spatial
# AR 3D: pose PENUH (posisi + kemiringan) + multi-model per ID marker.
# Scene (.tscn) TIDAK disentuh — node model di-spawn dari kode.
# C++ tidak diubah: rvec (axis-angle radian) dikonversi ke Basis di sini.

export var target_id: int = -1  # -1 = semua marker; >=0 = hanya ID itu
export var smooth_factor: float = 8.0  # lerp posisi (pisah dari rotasi)
export var smooth_rot: float = 8.0  # slerp rotasi (pisah dari posisi)
export var hold_frames: int = 12  # toleransi kedip: tahan pose N frame sebelum sembunyi
export var max_jump: float = 0.15  # meter; abaikan lompatan pose > ini per frame (0 = mati)
export var marker_length: float = 0.05  # meter; ukuran kubus fallback
export var model_scenes: Dictionary = {}  # {ID: PackedScene} — isi via Inspector setelah punya .glb
export var video_enabled: bool = true  # tampilkan frame kamera sebagai background 3D
export var video_distance: float = 1.0  # jarak quad video di depan kamera (meter)
export var capture_width: int = 640  # samakan dgn property width di ARWorker (C++)
export var capture_height: int = 480  # samakan dgn property height di ARWorker (C++)

var _nodes := {}  # ID(int) -> Node3D yang sedang tampil
var _missed := {}  # ID(int) -> jumlah frame beruntun tak terlihat
var _video_tex: ImageTexture
var _video_quad: MeshInstance


func _ready() -> void:
	# Cube di scene jadi TEMPLATE fallback (didup per ID), bukan pajangan.
	if has_node("Cube"):
		$Cube.visible = false
	_video_tex = ImageTexture.new()
	_sync_camera_fov()
	_set_status("Menunggu marker DICT_4X4_50...")


# Samakan FOV kamera Godot dgn fx OpenCV (0.9*width) agar kubus pas di atas
# marker pada video. Tanpa ini pose benar tapi terlihat meleset.
func _sync_camera_fov() -> void:
	if not has_node("Camera"):
		return
	if capture_width <= 0 or capture_height <= 0:
		return
	var fx := 0.9 * float(capture_width)
	var fov_y := rad2deg(2.0 * atan(float(capture_height) / (2.0 * fx)))
	($Camera as Camera).fov = fov_y


func _on_ARWorker_marker_detected(_node, ids: Array, translations: Array, rotations: Array) -> void:
	# TAHAP 1 — grace frames: jangan langsung sembunyi saat 1 frame gagal.
	# Hanya ID yang absen > hold_frames yang disembunyikan.
	if ids.empty():
		_tick_missed({})
		return

	var seen := {}
	var first_basis := Basis()
	var first_seen := false

	for i in range(ids.size()):
		var id := int(ids[i])
		if target_id >= 0 and id != target_id:
			continue
		if i >= translations.size() or i >= rotations.size():
			continue
		seen[id] = true
		_missed[id] = 0

		var t: Vector3 = translations[i]
		var r: Vector3 = rotations[i]
		# Konversi sumbu OpenCV (Y bawah, Z depan) ke Godot (Y atas, Z belakang).
		var pos := Vector3(t.x, -t.y, -t.z)
		var basis := _basis_from_rvec(r)
		if not first_seen:
			first_basis = basis
			first_seen = true

		var node: Spatial = _get_or_spawn(id)
		if not node.visible:
			node.transform = Transform(basis, pos)  # frame pertama: tempel langsung
		else:
			# TAHAP 1 — tolak outlier: abaikan pose yang meloncat tak wajar.
			if max_jump > 0.0 and node.translation.distance_to(pos) > max_jump:
				pos = node.translation
			var wp: float = clamp(smooth_factor * get_process_delta_time(), 0.0, 1.0)
			var wr: float = clamp(smooth_rot * get_process_delta_time(), 0.0, 1.0)
			var b: Basis = node.transform.basis.slerp(basis, wr)
			var p: Vector3 = node.translation.linear_interpolate(pos, wp)
			node.transform = Transform(b, p)
		node.visible = true

	_tick_missed(seen)

	var held := 0
	for id in _nodes.keys():
		if _missed.get(id, 0) > 0 and (_nodes[id] as Spatial).visible:
			held += 1

	_set_status(_status_text(ids, first_basis, first_seen, held))


# Tambah counter absen; sembunyikan hanya yg lewat batas. Kembalikan status dinamai.
func _tick_missed(seen: Dictionary) -> void:
	for id in _nodes.keys():
		if seen.has(id):
			continue
		_missed[id] = int(_missed.get(id, 0)) + 1
		if _missed[id] > hold_frames:
			(_nodes[id] as Spatial).visible = false
	if _nodes.empty() or _all_hidden():
		_set_status("Menunggu marker DICT_4X4_50...")


func _all_hidden() -> bool:
	for id in _nodes.keys():
		if (_nodes[id] as Spatial).visible:
			return false
	return true


# rvec = axis * angle (radian, koordinat OpenCV).
# F = diag(1,-1,-1) berdeterminan +1, sehingga F*R(axis,th)*F = R(F*axis, th).
# Jadi cukup balik Y/Z sumbu lalu Basis(axis, angle) — identik dgn Rodrigues di C++.
func _basis_from_rvec(r: Vector3) -> Basis:
	var angle := r.length()
	if angle < 0.0001:
		return Basis()
	var axis: Vector3 = r / angle
	return Basis(Vector3(axis.x, -axis.y, -axis.z), angle)


func _get_or_spawn(id: int) -> Spatial:
	if _nodes.has(id):
		return _nodes[id] as Spatial
	var node: Spatial = null
	if model_scenes.has(id) and model_scenes[id] is PackedScene:
		var inst: Node = (model_scenes[id] as PackedScene).instance()
		if inst is Spatial:
			node = inst
	if node == null and has_node("Cube"):
		node = $Cube.duplicate() as Spatial
		_tint(node, id)
	if node == null:
		node = _make_fallback_cube(id)
	add_child(node)
	node.visible = false
	_nodes[id] = node
	return node


# Beri warna unik per ID agar tiap marker mudah dibedakan.
func _tint(node: Spatial, id: int) -> void:
	if not (node is MeshInstance):
		return
	var mi := node as MeshInstance
	var src: Material = mi.get_surface_material(0)
	if src == null and mi.mesh != null and (mi.mesh as Mesh).get_surface_count() > 0:
		src = (mi.mesh as Mesh).surface_get_material(0)
	if src == null:
		return
	var m: Material = src.duplicate()
	if m is SpatialMaterial:
		var c := Color.from_hsv(fmod(float(abs(id)) * 0.37 + 0.08, 1.0), 0.85, 1.0)
		(m as SpatialMaterial).albedo_color = c
		(m as SpatialMaterial).emission = c
	mi.set_surface_material(0, m)


func _make_fallback_cube(id: int) -> MeshInstance:
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


func _hide_all(text: String) -> void:
	_missed.clear()
	for id in _nodes.keys():
		(_nodes[id] as Spatial).visible = false
	_set_status(text)


# TAHAP 2 — video background: gambar frame kamera pada quad di depan Camera.
# Kenapa quad, bukan TextureRect fullscreen: elemen Control selalu digambar DI
# ATAS 3D dalam satu viewport sehingga menutupi kubus. Quad punya depth benar.
func _on_ARWorker_frame_updated(_node, image) -> void:
	if not video_enabled or image == null:
		return
	_video_tex.create_from_image(image)
	_ensure_video_quad()


func _ensure_video_quad() -> void:
	if not has_node("Camera"):
		return
	if _video_quad != null and is_instance_valid(_video_quad):
		return
	var cam := $Camera as Camera
	var half_h := video_distance * tan(deg2rad(cam.fov * 0.5))
	var half_w := half_h * (float(capture_width) / float(max(capture_height, 1)))
	var quad := QuadMesh.new()
	quad.size = Vector2(half_w * 2.0, half_h * 2.0)
	var mat := SpatialMaterial.new()
	mat.flags_unshaded = true
	mat.flags_no_depth_test = false
	mat.params_billboard_mode = SpatialMaterial.BILLBOARD_DISABLED
	mat.albedo_texture = _video_tex
	# Emission agar tidak terpengaruh lampu scene (tampil seperti aslinya).
	mat.emission_enabled = true
	mat.emission_operator = SpatialMaterial.EMISSION_OP_ADD
	mat.emission = Color(1, 1, 1)
	mat.emission_texture = _video_tex
	var mi := MeshInstance.new()
	mi.name = "VideoQuad"
	mi.mesh = quad
	mi.set_surface_material(0, mat)
	cam.add_child(mi)
	mi.translation = Vector3(0, 0, -video_distance)
	_video_quad = mi


# Sudut = deviasi normal marker dari sumbu pandang kamera.
# 0° = tegak menghadap kamera; naik saat kertas/HP dimiringkan.
func _status_text(ids: Array, first_basis: Basis, first_seen: bool, held: int) -> String:
	var shown: Array = []
	for v in ids:
		var id := int(v)
		if target_id >= 0 and id != target_id:
			continue
		shown.append(id)
	if shown.empty():
		if target_id >= 0:
			return "Marker ID %d tidak terlihat..." % target_id
		return "Menunggu marker DICT_4X4_50..."
	var tilt_deg := 0.0
	if first_seen:
		tilt_deg = rad2deg(acos(clamp(first_basis.z.dot(Vector3(0, 0, 1)), -1.0, 1.0)))
	var s := "ID %s | miring %d°" % [str(shown), int(round(tilt_deg))]
	if held > 0:
		s += " | tahan %d" % held
	return s


func _set_status(text: String) -> void:
	if has_node("StatusLabel"):
		$StatusLabel.text = text
	else:
		print("[MainAR] ", text)
