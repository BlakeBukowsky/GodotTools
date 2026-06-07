@tool
extends RefCounted

# Read-side tools for the `user://` data directory — where games write save files,
# custom-level JSON, settings, etc. Agents couldn't peek at these without running
# the editor and eyeballing. Kept separate from fs.list (which is res://-only)
# because the semantics are different: user:// is runtime-written state, res:// is
# project source.

# user_fs.read — return a text file's content from user://.
# Params: {path}
static func read(params: Dictionary) -> Dictionary:
	var path: String = params.get("path", "")
	if path == "":
		return _err(-32602, "missing 'path'")
	if not path.begins_with("user://"):
		return _err(-32602, "path must begin with 'user://'")
	if not _within_sandbox(path, "user://"):
		return _err(-32602, "path escapes the user:// sandbox ('..' traversal not allowed): %s" % path)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return _err(-32001, "failed to open: %s (error %d)" % [path, FileAccess.get_open_error()])
	var size_bytes := f.get_length()
	var content := f.get_as_text()
	f.close()
	return _ok({
		"path": path,
		"content": content,
		"size_bytes": size_bytes,
	})


# user_fs.list — list entries under a user:// directory.
# Params: {dir?: "user://", recursive?: false}
static func list(params: Dictionary) -> Dictionary:
	var dir_path: String = params.get("dir", "user://")
	var recursive: bool = params.get("recursive", false)

	if not dir_path.begins_with("user://"):
		return _err(-32602, "dir must begin with 'user://'")
	if not _within_sandbox(dir_path, "user://"):
		return _err(-32602, "dir escapes the user:// sandbox ('..' traversal not allowed): %s" % dir_path)

	var files: Array = []
	var dirs: Array = []
	_walk(dir_path, files, dirs, recursive)

	files.sort()
	dirs.sort()
	return _ok({
		"dir": dir_path,
		"files": files,
		"dirs": dirs,
		"count": files.size(),
	})


static func _walk(dir_path: String, out_files: Array, out_dirs: Array, recursive: bool) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	while true:
		var name := d.get_next()
		if name == "":
			break
		if name.begins_with("."):
			continue
		var full := dir_path.path_join(name)
		if d.current_is_dir():
			out_dirs.append(full)
			if recursive:
				_walk(full, out_files, out_dirs, recursive)
		else:
			out_files.append(full)
	d.list_dir_end()


# Path-traversal guard — see fs_tools._within_sandbox. `begins_with("user://")`
# is not a sandbox; `..` segments resolve against the real filesystem.
static func _within_sandbox(path: String, prefix: String) -> bool:
	var root := ProjectSettings.globalize_path(prefix).simplify_path().trim_suffix("/")
	var abs := ProjectSettings.globalize_path(path).simplify_path()
	return abs == root or abs.begins_with(root + "/")


static func _ok(data) -> Dictionary:
	return {"data": data}


static func _err(code: int, msg: String) -> Dictionary:
	return {"error": {"code": code, "message": msg}}
