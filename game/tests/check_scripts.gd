extends SceneTree

## Compile-time gate used by `rr.py check`.
##
## Loads every runtime script in the project.  A script with a parse error
## loads to null and Godot prints the diagnostic, so the count below turns
## that noisy output into a single actionable exit status.

const ROOTS: PackedStringArray = ["res://src", "res://scenes"]

var _loaded: int = 0
var _broken: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	for root in ROOTS:
		_scan(root)
	if _broken.is_empty():
		print("check: %d runtime scripts import cleanly" % _loaded)
		quit(0)
		return
	for entry in _broken:
		print("check: BROKEN " + entry)
	print("check: %d scripts imported, %d broken" % [_loaded, _broken.size()])
	quit(1)


func _scan(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			if name != "." and name != "..":
				_scan(full)
		elif name.ends_with(".gd"):
			var script: Script = load(full)
			if script == null or not script.can_instantiate():
				_broken.append(full)
			else:
				_loaded += 1
		elif name.ends_with(".tscn") or name.ends_with(".tres"):
			var resource: Resource = load(full)
			if resource == null:
				_broken.append(full)
			else:
				_loaded += 1
		name = dir.get_next()
	dir.list_dir_end()
