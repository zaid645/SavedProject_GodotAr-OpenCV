extends Spatial
# Logika AR 3D: kubus CubeMesh menempel mengikuti marker ArUco.
# File ini SAJA yang dibuat — scene-nya (Main3D.tscn) dibuat manual
# mengikuti scene_implementation.md (node ARWorker + Cube + StatusLabel
# + koneksi sinyal marker_detected).
#
# Keputusan user: marker dari layar ponsel (tanpa print fisik),
# konten default CubeMesh, marker_length default 0.05 m.

export var target_id: int = -1  # -1 = marker apa saja (ID pertama); >=0 = hanya ID itu
export var smooth_factor: float = 8.0  # lerp pose agar kubus tidak bergetar
export var marker_length: float = 0.05  # meter; samakan dengan set_marker_length di C++

var _has_pose: bool = false


func _ready() -> void:
	if has_node("Cube"):
		$Cube.visible = false
	_set_status("Menunggu marker DICT_4X4_50...")


func _on_ARWorker_marker_detected(_node, ids: Array, translations: Array, _rotations: Array) -> void:
	if ids.empty() or translations.empty():
		_hide_cube("Menunggu marker DICT_4X4_50...")
		return

	# Pilih index: ID pertama, atau ID target bila diminta (multi-marker).
	var idx: int = 0
	if target_id >= 0:
		idx = ids.find(target_id)
		if idx < 0 or idx >= translations.size():
			_hide_cube("Marker ID %d tidak terlihat..." % target_id)
			return

	var t: Vector3 = translations[idx]
	# Konversi sumbu OpenCV (Y bawah, Z depan) ke Godot (Y atas, Z belakang).
	var godot_pos := Vector3(t.x, -t.y, -t.z)

	if not has_node("Cube"):
		return

	if not _has_pose:
		# Frame pertama: tempel langsung, hindari lerp dari origin.
		$Cube.translation = godot_pos
	else:
		$Cube.translation = $Cube.translation.linear_interpolate(godot_pos, clamp(smooth_factor * get_process_delta_time(), 0.0, 1.0))

	# Tahap 1: rotasi belum diterapkan penuh (butuh matriks Rodrigues dari C++).
	# Kubus tetap tegak; posisi sudah mengikuti marker.
	$Cube.visible = true
	_has_pose = true
	_set_status("Marker ID: %s" % str(ids[idx]))


func _hide_cube(text: String) -> void:
	_has_pose = false
	if has_node("Cube"):
		$Cube.visible = false
	_set_status(text)


func _set_status(text: String) -> void:
	if has_node("StatusLabel"):
		$StatusLabel.text = text
	else:
		print("[MainAR] ", text)
