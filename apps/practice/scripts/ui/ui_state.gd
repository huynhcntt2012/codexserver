extends Node
## Demo-only single source of truth. Real commerce must be server-authoritative.
signal wallet_changed
signal inventory_changed
signal loadout_changed
signal profile_changed
signal toast_requested(message: String)

const ITEM_PATH = "res://data/ui/items.json"
const CHAR_PATH = "res://data/ui/characters.json"
const PROFILE_PATH = "res://data/ui/demo_profile.json"
const SLOTS = ["hat", "outfit", "bomb_skin", "effect", "pet", "accessory"]
var items: Array = []
var characters: Array = []
var profile: Dictionary = {}
var catalog_by_id: Dictionary = {}
var hero_loadouts: Dictionary = {}

func _ready() -> void:
	items = _load_array(ITEM_PATH)
	characters = _load_array(CHAR_PATH)
	for entry in items:
		if entry is Dictionary:
			catalog_by_id[str(entry.get("id", ""))] = entry
	var d = _load_json(PROFILE_PATH)
	if d is Dictionary:
		profile = d
	# The UI demo starts from a deterministic fixture on every launch.
	# No real payment, cloud balance or personal account is used.

func _load_json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func _load_array(path: String) -> Array:
	var result = _load_json(path)
	if result is Array:
		return result
	push_error("Expected JSON array: " + path)
	return []

func get_item(item_id: String) -> Dictionary:
	return catalog_by_id.get(item_id, {})

func get_character(id: String) -> Dictionary:
	for c in characters:
		if str(c.get("id", "")) == id:
			return c
	return {}

func owned(item_id: String) -> bool:
	return item_id in profile.get("owned", [])

func equipped(item_id: String) -> bool:
	return item_id in profile.get("loadout", {}).values()

func buy(item_id: String) -> bool:
	var item = get_item(item_id)
	if item.is_empty() or not bool(item.get("shop_enabled", false)):
		toast_requested.emit("Vật phẩm không có trong cửa hàng")
		return false
	var currency = str(item.get("currency", "gold"))
	if currency not in ["gold", "gem"]:
		return false
	var cost = int(item.get("price", 0))
	if cost < 0:
		return false
	if str(item.get("category", "")) != "consumable" and owned(item_id):
		toast_requested.emit("Bạn đã sở hữu vật phẩm")
		return false
	if int(profile.get(currency, 0)) < cost:
		toast_requested.emit("Không đủ " + ("vàng" if currency == "gold" else "kim cương"))
		return false
	profile[currency] = int(profile.get(currency, 0)) - cost
	if str(item.get("category", "")) == "consumable":
		var stock: Dictionary = profile.get("consumables", {})
		stock[item_id] = int(stock.get(item_id, 0)) + int(item.get("quantity", 1))
		profile["consumables"] = stock
	else:
		var ownership: Array = profile.get("owned", [])
		ownership.append(item_id)
		profile["owned"] = ownership
	wallet_changed.emit()
	inventory_changed.emit()
	toast_requested.emit("Đã mua: " + str(item.get("name", "")))
	return true

func equip(item_id: String) -> bool:
	var item = get_item(item_id)
	var cat = str(item.get("category", ""))
	if cat not in SLOTS or not owned(item_id):
		toast_requested.emit("Vật phẩm chưa sở hữu hoặc không thể trang bị")
		return false
	var bound_hero = str(item.get("character_id", ""))
	if not bound_hero.is_empty() and bound_hero != str(profile.get("selected_character", "")):
		toast_requested.emit("Trang phục chỉ dành cho nhân vật " + bound_hero.to_upper())
		return false
	var loadout: Dictionary = profile.get("loadout", {})
	loadout[cat] = item_id
	profile["loadout"] = loadout
	loadout_changed.emit()
	toast_requested.emit("Đã trang bị: " + str(item.get("name", "")))
	return true

func choose_hero(hero_id: String) -> void:
	if get_character(hero_id).is_empty():
		return
	var previous = str(profile.get("selected_character", ""))
	if hero_id == previous:
		return
	hero_loadouts[previous] = profile.get("loadout", {}).duplicate(true)
	profile["selected_character"] = hero_id
	profile["loadout"] = hero_loadouts.get(hero_id, {}).duplicate(true)
	profile_changed.emit()
	loadout_changed.emit()

func reset_demo() -> void:
	hero_loadouts.clear()
	var d = _load_json(PROFILE_PATH)
	if d is Dictionary:
		profile = d
	wallet_changed.emit()
	inventory_changed.emit()
	loadout_changed.emit()
	profile_changed.emit()
	toast_requested.emit("Đã đặt lại dữ liệu demo")
