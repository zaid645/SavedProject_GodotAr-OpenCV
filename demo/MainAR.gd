extends Spatial
# AR 3D: pose PENUH (posisi + kemiringan) + multi-model per ID marker.
# Scene (.tscn) TIDAK disentuh — node model di-spawn dari kode.
# C++ tidak diubah: rvec (axis-angle radian) dikonversi ke Basis di sini.

export var target_id: int = -1  # -1 = semua marker; >=0 = hanya ID itu
export var smooth_factor: float = 8.0  # lerp posisi + slerp rotasi
export var marker_length: float = 0.05  # meter; ukuran kubus fallback
export var model_scenes: Dictionary = {}  # {ID: PackedScene} — isi via Inspector setelah punya .glb

var _nodes := {}  # ID(int) -> Node3D yang sedang tampil


func _ready() -> void:
	# Cube di scene jadi TEMPLATE fallback (didup per ID), bukan pajangan.
	if has_node("Cube"):
		$Cube.visible = false
	_set_status("Menunggu marker DICT_4X4_50...")


func _on_ARWorker_marker_detected(_node, ids: Array, translations: Array, rotations: Array) -> void:
	if ids.empty():
		_hide_all("Menunggu marker DICT_4X4_50...")
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
			var w: float = clamp(smooth_factor * get_process_delta_time(), 0.0, 1.0)
			var b: Basis = node.transform.basis.slerp(basis, w)
			var p: Vector3 = node.translation.linear_interpolate(pos, w)
			node.transform = Transform(b, p)
		node.visible = true

	for id in _nodes.keys():
		if not seen.has(id):
			(_nodes[id] as Spatial).visible = false

	_set_status(_status_text(ids, first_basis, first_seen))


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
	for id in _nodes.keys():
		(_nodes[id] as Spatial).visible = false
	_set_status(text)


# Sudut = deviasi normal marker dari sumbu pandang kamera.
# 0° = tegak menghadap kamera; naik saat kertas/HP dimiringkan.
func _status_text(ids: Array, first_basis: Basis, first_seen: bool) -> String:
	var shown: Array = []
	for v in ids:
		var id := int(v)
		if target_id >= 0 and id != target_id:
			continue
		shown.append(id)
	if shown.empty():
		return "Marker ID %d tidak terlihat..." % target_id
	var tilt_deg := 0.0
	if first_seen:
		tilt_deg = rad2deg(acos(clamp(first_basis.z.dot(Vector3(0, 0, 1)), -1.0, 1.0)))
	return "ID %s | miring %d°" % [str(shown), int(round(tilt_deg))]


func _set_status(text: String) -> void:
	if has_node("StatusLabel"):
		$StatusLabel.text = text
	else:
		print("[MainAR] ", text)


func _on_ARWorker_frame_updated(node, image):
	pass # Replace with function body.
