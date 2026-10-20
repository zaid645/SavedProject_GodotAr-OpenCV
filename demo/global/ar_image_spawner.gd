extends Spatial
class_name ARImageSpawner
# ARImageSpawner — kembaran ARMarkerSpawner utk kunci String (nama target).
# Jalur ArUco TIDAK disentuh. Handler: _on_images(names,translations,rotations).

signal spawned(name, instance)
signal despawned(name)

export var auto_create_session: bool = true
export var session_node: NodePath
export var target_map: Dictionary = {}
export var smooth_factor: float = 12.0
export var smooth_rot: float = 8.0
export var hold_frames: int = 5
export var max_jump: float = 0.30
export var target_width_m: float = 0.10
export var fallback_cube: bool = true
export var debug_mode: bool = true
export var status_label_path: NodePath

var _session: ARImageSession
var _instances := {}
var _missed := {}
var _spawned := {}


func _ready() -> void:
	_find_or_create_session()
	if _session == null:
		push_warning("[ARImageSpawner] Tidak ada ARImageSession.")
		return
	_session.connect("image_detected", self, "_on_images")
	_session.connect("status_changed", self, "_on_status")
	if not _session.is_running():
		_session.start()
	_refresh_from_library()
	_set_status("Menunggu image target...")


func _find_or_create_session() -> void:
	if session_node != NodePath(""):
		var n := get_node_or_null(session_node)
		if n is ARImageSession:
			_session = n
			return
	var existing := _find_session_recursive(get_tree().current_scene)
	if existing != null:
		_session = existing
		return
	if auto_create_session:
		_session = ARImageSession.new()
		_session.name = "ARImageSession"
		add_child(_session)


func _find_session_recursive(n: Node) -> ARImageSession:
	if n is ARImageSession:
		return n as ARImageSession
	for c in n.get_children():
		var f: ARImageSession = _find_session_recursive(c)
		if f != null:
			return f
	return null


func _refresh_from_library() -> void:
	var lib := _find_library()
	if lib == null:
		return
	for e in lib.list_targets():
		if e is Dictionary:
			var nm := str(e.get("name", ""))
			var sp := str(e.get("scene_path", ""))
			if nm != "" and sp != "" and not target_map.has(nm) and ResourceLoader.exists(sp):
				target_map[nm] = load(sp)


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
func _on_images(names: Array, translations: Array, rotations: Array) -> void:
	if names.empty():
		_tick_missed({})
		return
	var seen := {}
	for i in range(names.size()):
		var nm := str(names[i])
		if i >= translations.size() or i >= rotations.size():
			continue
		seen[nm] = true
		_missed[nm] = 0
		var t: Vector3 = translations[i]
		var pos := Vector3(t.x, -t.y, -t.z)
		var basis := ARImageSession.basis_from_rvec(rotations[i])
		var node: Spatial = _ensure_instance(nm)
		if node == null:
			continue
		if not _spawned.get(nm, false):
			node.transform = Transform(basis, pos)
			node.visible = true
			_spawned[nm] = true
			emit_signal("spawned", nm, node)
		else:
			var target: Vector3 = pos
			if max_jump > 0.0:
				var delta_p: Vector3 = target - node.translation
				var dist: float = delta_p.length()
				if dist > max_jump:
					target = node.translation + delta_p / dist * max_jump
			var wp: float = clamp(smooth_factor * get_process_delta_time(), 0.0, 1.0)
			var wr: float = clamp(smooth_rot * get_process_delta_time(), 0.0, 1.0)
			var b: Basis = node.transform.basis.slerp(basis, wr)
			var p: Vector3 = node.translation.linear_interpolate(target, wp)
			node.transform = Transform(b, p)
			node.visible = true
	_tick_missed(seen)


func _ensure_instance(nm: String) -> Spatial:
	if _instances.has(nm):
		return _instances[nm] as Spatial
	var node: Spatial = null
	if target_map.has(nm) and target_map[nm] is PackedScene:
		var inst: Node = (target_map[nm] as PackedScene).instance()
		if inst is Spatial:
			node = inst
	if node == null:
		if not debug_mode:
			return null
		if not fallback_cube:
			return null
		node = _make_cube(nm)
	if node == null:
		return null
	add_child(node)
	node.visible = false
	_instances[nm] = node
	return node


func _make_cube(nm: String) -> MeshInstance:
	var mi := MeshInstance.new()
	var box := CubeMesh.new()
	box.size = Vector3(target_width_m, target_width_m, target_width_m)
	mi.mesh = box
	var mat := SpatialMaterial.new()
	var hue := fmod(float(abs(nm.hash())) / 4294967295.0 + 0.08, 1.0)
	var c := Color.from_hsv(hue, 0.85, 1.0)
	mat.albedo_color = c
	mat.emission_enabled = true
	mat.emission = c
	mi.set_surface_material(0, mat)
	return mi


func _tick_missed(seen: Dictionary) -> void:
	for nm in _instances.keys():
		if seen.has(nm):
			continue
		_missed[nm] = int(_missed.get(nm, 0)) + 1
		if _missed[nm] > hold_frames:
			var n := _instances[nm] as Spatial
			n.visible = false
			emit_signal("despawned", nm)
			n.queue_free()
			_instances.erase(nm)
			_spawned.erase(nm)
			_missed.erase(nm)
	if _instances.empty() or _all_hidden():
		_set_status("Menunggu image target...")


func _all_hidden() -> bool:
	for nm in _instances.keys():
		if (_instances[nm] as Spatial).visible:
			return false
	return true


func _on_status(text: String) -> void:
	if not debug_mode:
		return
	_set_status(text)


func _set_status(text: String) -> void:
	if not debug_mode:
		return
	if status_label_path != NodePath(""):
		var lbl := get_node_or_null(status_label_path)
		if lbl != null and lbl is Label:
			lbl.text = text


func add_target_scene(nm: String, scene: PackedScene) -> void:
	if scene != null:
		target_map[nm] = scene


func clear_targets() -> void:
	target_map.clear()


func target_names() -> Array:
	return target_map.keys()

			return f
	return null
