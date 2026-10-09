extends Control
# Debug video 2D: tampilkan frame webcam + paksa deteksi aktif.
# Catatan: .tscn TIDAK diubah (sesuai batasan) — semua diamankan via kode.

var _tex: ImageTexture


func _ready() -> void:
	_tex = ImageTexture.new()

	# Paksa deteksi aktif walau properti show_processed di .tscn lupa dicentang (G1).
	if has_node("Sprite"):
		$Sprite.set_show_processed(true)

	_set_status("Menunggu marker DICT_4X4_50...")


func _on_Sprite_frame_updated(_node, image) -> void:
	# Reuse SATU texture, jangan ImageTexture.new() tiap frame (G2).
	if image == null:
		return
	_tex.create_from_image(image)
	if has_node("webcamView"):
		$webcamView.texture = _tex


func _on_Sprite_marker_detected(_node, ids: Array, _translations: Array, _rotations: Array) -> void:
	# Status ringan untuk debug 2D. Untuk AR 3D pakai MainAR.gd.
	if ids.empty():
		_set_status("Menunggu marker DICT_4X4_50...")
	else:
		_set_status("Marker ID: %s" % str(ids[0]))


func _set_status(text: String) -> void:
	# Guard: StatusLabel dibuat manual via scene_implementation.md (G5).
	# Tanpa guard ini game crash bila label belum ada.
	if has_node("StatusLabel"):
		$StatusLabel.text = text
	else:
		print("[Main2D] ", text)

