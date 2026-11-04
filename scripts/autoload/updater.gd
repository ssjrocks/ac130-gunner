extends Node
## Checks the GitHub releases of this game for a newer version and installs
## it in place: downloads the platform zip, swaps the executable, restarts.
## Only active in exported builds.

signal changed

const REPO := "ssjrocks/ac130-gunner"

var status := "idle"   # idle checking current available downloading ready error disabled
var latest := ""
var asset_url := ""
var notes := ""
var error := ""
var progress := 0.0
var http: HTTPRequest
var dl: HTTPRequest
var zip_path := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	http = HTTPRequest.new()
	http.timeout = 20.0
	add_child(http)
	http.request_completed.connect(_on_checked)
	dl = HTTPRequest.new()
	dl.timeout = 600.0
	add_child(dl)
	dl.request_completed.connect(_on_downloaded)
	zip_path = OS.get_user_data_dir().path_join("update.zip")
	if not enabled():
		status = "disabled"
		return
	_cleanup_old()
	get_tree().create_timer(2.0).timeout.connect(check)


func enabled() -> bool:
	if OS.get_environment("AC130_UPDATE_URL") != "":
		return true
	return OS.has_feature("template") and Game.autotest == ""


static func current_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


static func newer(a: String, b: String) -> bool:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return x > y
	return false


func _platform_key() -> String:
	return "windows" if OS.get_name() == "Windows" else "linux"


func check() -> void:
	if status == "checking" or status == "downloading":
		return
	status = "checking"
	changed.emit()
	var url := OS.get_environment("AC130_UPDATE_URL")
	if url == "":
		url = "https://api.github.com/repos/%s/releases/latest" % REPO
	var err := http.request(url, ["User-Agent: ac130-gunner", "Accept: application/vnd.github+json"])
	if err != OK:
		_fail("could not start the update check")


func _on_checked(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("update check failed (%d/%d)" % [result, code])
		return
	var d = JSON.parse_string(body.get_string_from_utf8())
	if not d is Dictionary:
		_fail("bad release data")
		return
	latest = str(d.get("tag_name", "")).trim_prefix("v")
	notes = str(d.get("body", ""))
	if not newer(latest, current_version()):
		status = "current"
		changed.emit()
		return
	asset_url = ""
	for a in d.get("assets", []):
		var n: String = a.get("name", "")
		if n.ends_with(".zip") and n.contains(_platform_key()):
			asset_url = a.get("browser_download_url", "")
	if asset_url == "":
		_fail("no %s download in release %s" % [_platform_key(), latest])
		return
	status = "available"
	changed.emit()


func install() -> void:
	if status != "available":
		return
	status = "downloading"
	progress = 0.0
	changed.emit()
	dl.download_file = zip_path
	var err := dl.request(asset_url, ["User-Agent: ac130-gunner"])
	if err != OK:
		_fail("could not start the download")


func _process(_dt: float) -> void:
	if status == "downloading":
		var total := dl.get_body_size()
		if total > 0:
			progress = float(dl.get_downloaded_bytes()) / float(total)
			changed.emit()


func _on_downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("download failed (%d/%d)" % [result, code])
		return
	var err := _apply()
	if err != "":
		_fail(err)
		return
	status = "ready"
	changed.emit()


## Unpacks the new executable next to the running one and swaps them.
## Renaming a running executable works on both Linux and Windows.
func _apply() -> String:
	var zr := ZIPReader.new()
	if zr.open(zip_path) != OK:
		return "downloaded file is not a zip"
	var exe := OS.get_executable_path()
	var entry := ""
	for f in zr.get_files():
		if f.ends_with(".exe") or f.ends_with(".x86_64"):
			entry = f
	if entry == "":
		zr.close()
		return "no executable in the download"
	var bytes := zr.read_file(entry)
	zr.close()
	var newp := exe + ".new"
	var fa := FileAccess.open(newp, FileAccess.WRITE)
	if fa == null:
		return "cannot write next to the game (%s)" % exe.get_base_dir()
	fa.store_buffer(bytes)
	fa.close()
	if OS.get_name() != "Windows":
		OS.execute("chmod", ["+x", newp])
	var old := exe + ".old"
	if FileAccess.file_exists(old):
		DirAccess.remove_absolute(old)
	if DirAccess.rename_absolute(exe, old) != OK:
		return "cannot replace the running game"
	if DirAccess.rename_absolute(newp, exe) != OK:
		DirAccess.rename_absolute(old, exe)
		return "cannot move the new version into place"
	DirAccess.remove_absolute(zip_path)
	return ""


func restart() -> void:
	OS.create_process(OS.get_executable_path(), [])
	get_tree().quit()


func _cleanup_old() -> void:
	var old := OS.get_executable_path() + ".old"
	if FileAccess.file_exists(old):
		DirAccess.remove_absolute(old)


func _fail(msg: String) -> void:
	status = "error"
	error = msg
	push_warning("updater: " + msg)
	changed.emit()
