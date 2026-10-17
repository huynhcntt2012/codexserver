extends Node
## Every playable map: the 15 built-in level files plus maps an admin published on
## the server (public GET /v1/maps, ETag). Admin maps use the same level shape and
## only reference art the game ships; anything unusable is skipped, never guessed.
## Previews: built-in maps have a PNG, admin maps are rendered here from the layout.

signal changed

const GAME := preload("res://scripts/game.gd")
const REFRESH_GAP_MS := 10_000
const PREVIEW_CELL := 16

var builtin: Array[Dictionary] = []
var remote: Array[Dictionary] = []
var etag := ""
var busy := false
var last_refresh := -REFRESH_GAP_MS
var previews: Dictionary = {}  # "id:revision" -> Texture2D

func _ready() -> void:
	for path in GAME.LEVEL_FILES:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary:
			builtin.append(data)
	refresh()

func all() -> Array[Dictionary]:
	return builtin + remote

func level_at(index: int) -> Dictionary:
	var maps := all()
	return maps[clampi(index, 0, maps.size() - 1)]

func index_of(map_id: String) -> int:
	var maps := all()
	for i in maps.size():
		if str(maps[i].get("id", "")) == map_id:
			return i
	return -1

func find(map_id: String) -> Dictionary:
	var index := index_of(map_id)
	return all()[index] if index >= 0 else {}

## Newly published maps show up while the app stays open: ask again every 30 s
## (a 304 when nothing changed).
const POLL_MS := 30_000

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() - last_refresh >= POLL_MS:
		refresh()

## Fetches published admin maps (at most every 10 s; 304 when unchanged).
func refresh(force := false) -> void:
	if busy or OS.get_environment("SUNI_OFFLINE") == "1":
		return
	if not force and Time.get_ticks_msec() - last_refresh < REFRESH_GAP_MS:
		return
	busy = true
	last_refresh = Time.get_ticks_msec()
	var request := HTTPRequest.new()
	request.timeout = 8.0
	request.max_redirects = 0
	request.body_size_limit = 1_048_576
	add_child(request)
	var headers := PackedStringArray()
	if etag != "":
		headers.append("If-None-Match: " + etag)
	var data: Variant = null
	var status := 0
	if request.request(AuthSession.api_url + "/v1/maps", headers) == OK:
		var response: Array = await request.request_completed
		status = int(response[1]) if response[0] == HTTPRequest.RESULT_SUCCESS else 0
		if status == 200:
			data = JSON.parse_string(response[3].get_string_from_utf8())
			for header in response[2]:
				if str(header).to_lower().begins_with("etag:"):
					etag = str(header).substr(5).strip_edges()
	request.queue_free()
	busy = false
	if status == 200 and data is Dictionary:
		apply(data.get("maps", []))

## Keeps the valid admin maps; emits `changed` when the list differs.
func apply(entries: Variant) -> void:
	var found: Array[Dictionary] = []
	var taken := {}
	for entry in builtin:
		taken[str(entry.id)] = true
	if entries is Array:
		for entry in entries:
			if entry is Dictionary and usable(entry) and not taken.has(str(entry.id)):
				taken[str(entry.id)] = true
				found.append(entry)
	if JSON.stringify(found) != JSON.stringify(remote):
		remote = found
		changed.emit()

## Same limits as the API and arena, plus: every art file exists in this build.
static func usable(level: Dictionary) -> bool:
	var columns := int(level.get("columns", 0))
	var rows := int(level.get("rows", 0))
	var layout: Variant = level.get("layout")
	var spawns: Variant = level.get("spawns")
	if not (str(level.get("id", "")).is_valid_identifier() and columns >= 11 and columns <= 21 and rows >= 9 and rows <= 17):
		return false
	if not (layout is Array and layout.size() == rows and spawns is Array and spawns.size() == 4):
		return false
	for line in layout:
		if not (line is String and line.length() == columns):
			return false
		for ch in line:
			if not ch in ["#", "C", "."]:
				return false
	for point in spawns:
		if not (point is Array and point.size() == 2):
			return false
		var x := int(point[0])
		var y := int(point[1])
		if x < 1 or y < 1 or x >= columns - 1 or y >= rows - 1 or str(layout[y])[x] != ".":
			return false
	for path in art_paths(level):
		if not ResourceLoader.exists(path):
			return false
	return true

static func art_paths(level: Dictionary) -> Array[String]:
	var paths: Array[String] = [
		"res://assets/obstacles/%s/00.png" % level.get("wall", ""),
		"res://assets/obstacles/%s/00.png" % level.get("crate", ""),
		"res://assets/bombs/%s.png" % level.get("bomb", ""),
		"res://assets/effects/%s/00.png" % level.get("fx", ""),
	]
	for n in 2:
		for m in 4:
			paths.append("res://assets/tiles/%s/%d_%d.png" % [level.get("theme", ""), n, m])
	return paths

## Card art: the shipped PNG, or a render of an admin map (cached per revision).
func preview(map_id: String) -> Texture2D:
	var path := "res://assets/level_previews/%s.png" % map_id
	if ResourceLoader.exists(path):
		return load(path)
	var entry := find(map_id)
	if entry.is_empty():
		return null
	var key := "%s:%s" % [map_id, entry.get("revision", 0)]
	if not previews.has(key):
		previews[key] = ImageTexture.create_from_image(render(entry))
	return previews[key]

static func render(level: Dictionary) -> Image:
	var columns := int(level.columns)
	var rows := int(level.rows)
	var out := Image.create(columns * PREVIEW_CELL, rows * PREVIEW_CELL, false, Image.FORMAT_RGBA8)
	var floors := []
	for n in 2:
		for m in 4:
			floors.append(cell_image("res://assets/tiles/%s/%d_%d.png" % [level.theme, n, m]))
	var wall := cell_image("res://assets/obstacles/%s/00.png" % level.wall)
	var crate := cell_image("res://assets/obstacles/%s/00.png" % level.crate)
	for y in rows:
		var line: String = level.layout[y]
		for x in columns:
			var at := Vector2i(x, y) * PREVIEW_CELL
			var ground: Image = floors[(y % 2) * 4 + ((x + y) % 4)]
			out.blit_rect(ground, Rect2i(Vector2i.ZERO, ground.get_size()), at)
			var piece: Image = wall if line[x] == "#" else (crate if line[x] == "C" else null)
			if piece:
				out.blend_rect(piece, Rect2i(Vector2i.ZERO, piece.get_size()), at)
	return out

static func cell_image(path: String) -> Image:
	var image: Image = (load(path) as Texture2D).get_image()
	image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	image.resize(PREVIEW_CELL, PREVIEW_CELL, Image.INTERPOLATE_BILINEAR)
	return image
