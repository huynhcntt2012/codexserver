extends Node
## UI state. Guests use the local demo fixture; signed-in players use the server
## wallet and inventory (prices, balances and purchases are decided by the API).
signal wallet_changed
signal inventory_changed
signal loadout_changed
signal profile_changed
signal toast_requested(message: String)

const ITEM_PATH = "res://data/ui/items.json"
const CHAR_PATH = "res://data/ui/characters.json"
const PROFILE_PATH = "res://data/ui/demo_profile.json"
const SLOTS = ["hat", "wings", "outfit", "bomb_skin", "effect", "pet", "accessory"]
var items: Array = []
var characters: Array = []
var profile: Dictionary = {}
var catalog_by_id: Dictionary = {}
var hero_loadouts: Dictionary = {}
var online_wallet := false
var _signed_in := false
var _buying := false

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

## The pet brought into a round: the equipped one, else the first owned (it is
## also the Q mount). Online, the arena checks ownership again.
func round_pet() -> String:
	var worn := str(profile.get("loadout", {}).get("pet", ""))
	if worn != "" and owned(worn):
		return worn
	for item in items:
		if str(item.get("category", "")) == "pet" and owned(str(item.get("id", ""))):
			return str(item.id)
	return ""

func _process(_delta: float) -> void:
	# Follow sign-in/out: server wallet while signed in, demo fixture otherwise.
	var signed_in: bool = AuthSession.has_session()
	if signed_in == _signed_in:
		return
	_signed_in = signed_in
	if signed_in:
		sync_wallet()
		var catalog := get_node_or_null("/root/CatalogSync")
		if catalog:
			catalog.sync()
	elif online_wallet:
		online_wallet = false
		reset_demo(false)

func sync_wallet() -> void:
	var reply: Dictionary = await AuthSession.api(HTTPClient.METHOD_GET, "/v1/wallet")
	if reply.status == 200 and reply.data is Dictionary:
		apply_wallet(reply.data)

func apply_wallet(data: Dictionary) -> void:
	online_wallet = true
	profile["gold"] = int(data.get("gold", 0))
	profile["gem"] = int(data.get("gem", 0))
	profile["owned"] = Array(data.get("owned", []))
	profile["consumables"] = Dictionary(data.get("stock", {}))
	var loadout: Dictionary = profile.get("loadout", {})
	for slot in loadout.keys():
		if str(loadout[slot]) != "" and not owned(str(loadout[slot])):
			loadout[slot] = ""
	wallet_changed.emit()
	inventory_changed.emit()
	loadout_changed.emit()

static func request_id() -> String:
	return Crypto.new().generate_random_bytes(12).hex_encode()

func buy_online(item_id: String) -> bool:
	if _buying:
		return false
	_buying = true
	var item := get_item(item_id)
	var reply: Dictionary = await AuthSession.api(HTTPClient.METHOD_POST, "/v1/shop/purchase", {"item_id": item_id, "request_id": request_id()})
	_buying = false
	if reply.status == 200 and reply.data is Dictionary:
		apply_wallet(reply.data)
		toast_requested.emit("Đã mua: " + str(item.get("name", "")))
		return true
	var message := str(reply.error)
	if reply.status == 409:
		message = "Không đủ " + ("kim cương" if str(item.get("currency", "gold")) == "gem" else "vàng") + " hoặc đã sở hữu"
	elif reply.status == 404:
		message = "Vật phẩm đã ngừng bán"
	toast_requested.emit(message)
	return false

func topup(pack_id: String) -> bool:
	var reply: Dictionary = await AuthSession.api(HTTPClient.METHOD_POST, "/v1/topup", {"pack_id": pack_id, "request_id": request_id()})
	if reply.status == 200 and reply.data is Dictionary:
		apply_wallet(reply.data)
		return true
	toast_requested.emit("Không đủ kim cương để đổi" if reply.status == 409 else str(reply.error))
	return false

func buy(item_id: String) -> bool:
	if online_wallet and AuthSession.has_session():
		buy_online(item_id)
		return true
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

## Empties a slot, so the hero can be seen without that item again.
func unequip(slot: String) -> void:
	var loadout: Dictionary = profile.get("loadout", {})
	var item := get_item(str(loadout.get(slot, "")))
	if item.is_empty():
		return
	loadout[slot] = ""
	profile["loadout"] = loadout
	loadout_changed.emit()
	toast_requested.emit("Đã tháo: " + str(item.get("name", "")))

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

func reset_demo(announce := true) -> void:
	hero_loadouts.clear()
	var d = _load_json(PROFILE_PATH)
	if d is Dictionary:
		profile = d
	wallet_changed.emit()
	inventory_changed.emit()
	loadout_changed.emit()
	profile_changed.emit()
	if announce:
		toast_requested.emit("Đã đặt lại dữ liệu demo")
