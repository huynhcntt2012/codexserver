extends Node
## Keeps the item catalog in step with the admin portal without slowing play:
## - The catalog JSON uses an ETag, so an unchanged catalog costs one 304.
## - Icons are content-addressed (sha256): each one downloads once, is checked
##   against its hash, then lives in user://catalog/icons forever.
## - At most MAX_PARALLEL downloads run, and none start while a match is running.
## - Until an icon arrives (or when offline) the bundled res:// art is used.
const HeroPortrait := preload("res://scripts/hero_portrait.gd")
signal catalog_applied()
signal icon_ready(item_id: String)

const DIR := "user://catalog"
const ICONS := "user://catalog/icons"
const MAX_PARALLEL := 3
var etag := ""
var server_items: Array = []
var queue: Array = []
var active := 0
var syncing := false
var paused := false  # set by the game while a round is in progress
var textures: Dictionary = {}

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ICONS)
	var cached = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/catalog.json")) if FileAccess.file_exists(DIR + "/catalog.json") else null
	if cached is Dictionary:
		etag = str(cached.get("etag", ""))
		apply(cached.get("items", []))
	sync.call_deferred()

## Local cache file for an icon; keeps the original folder so UI cropping rules still apply.
static func icon_path(entry: Dictionary) -> String:
	var folder := str(entry.get("icon", "")).get_base_dir()
	return "%s/%s/%s.png" % [ICONS, folder if folder != "" else "misc", entry.get("icon_sha256", "")]

func sync() -> void:
	if syncing or OS.get_environment("SUNI_OFFLINE") == "1":
		return
	syncing = true
	var request := HTTPRequest.new()
	request.timeout = 10.0
	request.max_redirects = 0
	request.body_size_limit = 1_048_576
	add_child(request)
	var headers := PackedStringArray()
	if etag != "":
		headers.append("If-None-Match: " + etag)
	if request.request(AuthSession.api_url + "/v1/catalog", headers) != OK:
		request.queue_free()
		syncing = false
		return
	var response: Array = await request.request_completed
	request.queue_free()
	syncing = false
	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return
	if response[1] == 200:
		var data = JSON.parse_string(response[3].get_string_from_utf8())
		if not data is Dictionary or not data.get("items") is Array:
			return
		for header in response[2]:
			if header.to_lower().begins_with("etag:"):
				etag = header.substr(5).strip_edges()
		var file := FileAccess.open(DIR + "/catalog.json", FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify({"etag": etag, "items": data.items}))
		apply(data.items)
	elif response[1] == 304:
		apply(server_items)

## Merges server items into UIState: server values win, unpublished local items
## leave the shop, and art switches to the cached server icon when present.
func apply(items: Array) -> void:
	server_items = items
	var listed := {}
	for entry in items:
		if not entry is Dictionary:
			continue
		var id := str(entry.get("id", ""))
		listed[id] = true
		var item: Dictionary = UIState.catalog_by_id.get(id, {})
		if item.is_empty():
			item = {"id": id, "quantity": 1}
			UIState.items.append(item)
			UIState.catalog_by_id[id] = item
		for key in ["name", "category", "rarity", "description", "price", "currency"]:
			if entry.has(key) and entry[key] != null:
				item[key] = entry[key]
		item["shop_enabled"] = true
		var bundled := "res://assets/" + str(entry.get("icon", ""))
		if HeroPortrait.for_path(bundled) != null:
			# A hero portrait (outfits) or a pet: the bundled animation, not a still copy.
			item["icon"] = bundled
			continue
		if not item.has("icon") or not has_icon(str(item.get("icon", ""))):
			item["icon"] = bundled if ResourceLoader.exists(bundled) else ""
		if str(entry.get("icon_sha256", "")) != "":
			var cached := icon_path(entry)
			if FileAccess.file_exists(cached):
				item["icon"] = cached
			elif not queue.any(func(q): return q.id == id):
				queue.append({"id": id, "entry": entry})
	if not items.is_empty():
		for item in UIState.items:
			if not listed.has(str(item.get("id", ""))):
				item["shop_enabled"] = false
	UIState.inventory_changed.emit()
	catalog_applied.emit()

func _process(_delta: float) -> void:
	while not paused and active < MAX_PARALLEL and not queue.is_empty():
		download(queue.pop_front())

func download(job: Dictionary) -> void:
	active += 1
	var entry: Dictionary = job.entry
	var request := HTTPRequest.new()
	request.timeout = 15.0
	request.max_redirects = 0
	request.body_size_limit = 11_000_000  # API icon cap is 10 MB
	add_child(request)
	if request.request(AuthSession.api_url + str(entry.get("icon_url", ""))) != OK:
		request.queue_free()
		active -= 1
		return
	var response: Array = await request.request_completed
	request.queue_free()
	active -= 1
	if response[0] != HTTPRequest.RESULT_SUCCESS or response[1] != 200:
		return
	var body: PackedByteArray = response[3]
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(body)
	# A corrupted or swapped file never reaches the cache.
	if hashing.finish().hex_encode() != str(entry.get("icon_sha256", "")):
		return
	var path := icon_path(entry)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_buffer(body)
	file.close()
	var item: Dictionary = UIState.catalog_by_id.get(str(job.id), {})
	if not item.is_empty():
		item["icon"] = path
	icon_ready.emit(str(job.id))
	UIState.inventory_changed.emit()

## Cached user:// icons are raw PNGs, not imported resources.
static func has_icon(path: String) -> bool:
	return FileAccess.file_exists(path) if path.begins_with("user://") else ResourceLoader.exists(path)

## Texture for a res:// or cached user:// icon; user files are decoded once.
func texture(path: String) -> Texture2D:
	if path == "":
		return null
	if not path.begins_with("user://"):
		var portrait := HeroPortrait.for_path(path)
		if portrait != null:
			return portrait
		return load(path) if ResourceLoader.exists(path) else null
	if textures.has(path):
		return textures[path]
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	var value := ImageTexture.create_from_image(image)
	textures[path] = value
	return value
