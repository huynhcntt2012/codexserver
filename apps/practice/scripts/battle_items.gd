extends Node
## Quick slot items and the mount in practice rounds (docs/BATTLE_ITEMS.md).
## Same rules and numbers as the arena (apps/arena/src/game.ts ITEM_RULES):
## counts come from the player's stock and each accepted use is consumed —
## signed in: POST /v1/inventory/use (the server stock), guest: the demo stock.

signal changed

const SLOTS := ["throw_bomb", "dart", "blue_shield", "speed_shoes", "freeze_bomb", "push_glove"]
const RULES := {
	"throw_bomb": {"cooldown": 5.0, "range": 3},
	"dart": {"cooldown": 0.8, "range": 5},
	"blue_shield": {"cooldown": 8.0, "range": 0},
	"speed_shoes": {"cooldown": 6.0, "range": 0},
	"freeze_bomb": {"cooldown": 6.0, "range": 2},
	"push_glove": {"cooldown": 5.0, "range": 8},
}
const SHIELD_TIME := 8.0
const SPEED_TIME := 5.0
const SLOW_TIME := 3.0
const GRACE_TIME := 0.6

var game: Node
var selected := 0
var counts: Dictionary = {}
var cooldowns: Dictionary = {}  # item -> game.elapsed when ready again
var facing := Vector2i.DOWN
var pet := ""
var mounted := false
var pet_used := false
var shield_until := 0.0
var speed_until := 0.0
var grace_until := 0.0

func start_round() -> void:
	var stock: Dictionary = UIState.profile.get("consumables", {})
	for id in SLOTS:
		counts[id] = clampi(int(stock.get(id, 0)), 0, 99)
	cooldowns.clear()
	facing = Vector2i.DOWN
	pet = ""
	for item in UIState.items:
		if str(item.get("category", "")) == "pet" and UIState.owned(str(item.id)):
			pet = str(item.id)
			break
	mounted = false
	pet_used = false
	shield_until = 0.0
	speed_until = 0.0
	grace_until = 0.0
	changed.emit()

func now() -> float:
	return float(game.elapsed)

func cooldown_left(id: String) -> float:
	return maxf(0.0, float(cooldowns.get(id, 0.0)) - now())

func select(index: int) -> void:
	selected = clampi(index, 0, SLOTS.size() - 1)
	changed.emit()

## Movement speed factor for the player (boots x1.35, mount x1.25).
func speed_factor() -> float:
	var factor := 1.0
	if speed_until > now():
		factor *= 1.35
	if mounted:
		factor *= 1.25
	return factor

## A shield or the mount takes a hit instead of the player; true = absorbed.
func absorb_hit() -> bool:
	if grace_until > now():
		return true
	if shield_until > now():
		shield_until = 0.0
	elif mounted:
		mounted = false
		pet_used = true
		game._flash_status("Thú cưỡi đã đỡ một đòn cho bạn!")
	else:
		return false
	grace_until = now() + GRACE_TIME
	game._sound("hit")
	changed.emit()
	return true

func toggle_mount() -> bool:
	if pet == "" or game.player.is_empty() or not game.player.alive:
		game._flash_status("Chưa có thú cưỡi. Mua pet ở Cửa hàng.")
		return false
	if pet_used and not mounted:
		game._flash_status("Thú cưỡi đã đỡ đòn, chờ ván sau.")
		return false
	mounted = not mounted
	game._flash_status("Đang cưỡi thú: +25% tốc độ, đỡ 1 đòn." if mounted else "Đã xuống thú.")
	changed.emit()
	return true

func use_selected() -> bool:
	return use_item(str(SLOTS[selected]))

## Applies one item in the facing direction; consumed only when it does something.
func use_item(id: String) -> bool:
	var actor: Dictionary = game.player
	if actor.is_empty() or not actor.alive or int(counts.get(id, 0)) <= 0 or cooldown_left(id) > 0.0:
		return false
	var origin: Vector2i = actor.cell
	var ok := false
	match id:
		"throw_bomb":
			var target := origin
			for d in range(1, int(RULES.throw_bomb.range) + 1):
				var cell: Vector2i = origin + facing * d
				if game.terrain.has(cell) or not game._inside(cell):
					break
				if not game.crates.has(cell) and game._bomb_at(cell).is_empty() and not game._fighter_at(cell):
					target = cell
			if target != origin:
				game._spawn_bomb(actor, target, true)
				ok = true
		"dart":
			for d in range(1, int(RULES.dart.range) + 1):
				var cell: Vector2i = origin + facing * d
				if game.terrain.has(cell) or game.crates.has(cell) or not game._inside(cell):
					break
				var bomb: Dictionary = game._bomb_at(cell)
				if not bomb.is_empty():
					game._explode_bomb(bomb)
					break
			ok = true
		"blue_shield":
			shield_until = now() + SHIELD_TIME
			ok = true
		"speed_shoes":
			speed_until = now() + SPEED_TIME
			ok = true
		"freeze_bomb":
			var center := origin
			for d in range(1, int(RULES.freeze_bomb.range) + 1):
				var cell: Vector2i = origin + facing * d
				if game.terrain.has(cell) or game.crates.has(cell):
					break
				center = cell
			for other in game.fighters:
				if other != actor and other.alive and absi(other.cell.x - center.x) <= 1 and absi(other.cell.y - center.y) <= 1:
					other["slow_until"] = now() + SLOW_TIME
					other.root.modulate = Color("9fe4ff")
			game._splash_at(center, "ice")
			ok = true
		"push_glove":
			var bomb: Dictionary = game._bomb_at(origin + facing)
			if not bomb.is_empty():
				var cell: Vector2i = bomb.cell
				for d in range(int(RULES.push_glove.range)):
					var next: Vector2i = cell + facing
					if not game._can_walk(next) or game._fighter_at(next):
						break
					cell = next
				if cell != bomb.cell:
					bomb.cell = cell
					bomb.node.create_tween().tween_property(bomb.node, "position", game._cell_center(cell), 0.18)
					ok = true
	if not ok:
		return false
	counts[id] = int(counts[id]) - 1
	cooldowns[id] = now() + float(RULES[id].cooldown)
	_consume(id)
	game._sound("place_bomb")
	changed.emit()
	return true

func _consume(id: String) -> void:
	var stock: Dictionary = UIState.profile.get("consumables", {})
	stock[id] = maxi(0, int(stock.get(id, 0)) - 1)
	UIState.profile["consumables"] = stock
	if AuthSession.has_session():
		AuthSession.api(HTTPClient.METHOD_POST, "/v1/inventory/use", {"item_id": id, "request_id": UIState.request_id()})

## Bots under "Bom đóng băng" move 1.6x slower; the tint fades when it ends.
func bot_step_factor(actor: Dictionary) -> float:
	if float(actor.get("slow_until", 0.0)) > now():
		return 1.6
	if actor.has("slow_until"):
		actor.erase("slow_until")
		actor.root.modulate = Color.WHITE if actor.alive else actor.root.modulate
	return 1.0

## HUD state (same shape the online HUD builds from the server snapshot).
func view() -> Dictionary:
	var slots := []
	for id in SLOTS:
		slots.append({"id": id, "count": int(counts.get(id, 0)), "cooldown": cooldown_left(id), "cooldown_total": float(RULES[id].cooldown)})
	return {
		"slots": slots,
		"selected": selected,
		"pet": pet,
		"mounted": mounted,
		"pet_used": pet_used,
		"shield": shield_until > now(),
		"fast": speed_until > now(),
	}

## Marks on the player's own sprite: shield bubble, mount under the feet, speed glow.
func _process(_delta: float) -> void:
	if game == null or game.player.is_empty() or not is_instance_valid(game.player.root):
		return
	var holder: Node2D = game.player.root
	_mark(holder, "ItemShield", "res://assets/items/shield.png", shield_until > now(), Vector2(0, -26), 0.42, -1)
	var pet_icon := str(UIState.get_item(pet).get("icon", "")) if pet != "" else ""
	_mark(holder, "ItemMount", pet_icon, mounted and pet_icon != "", Vector2(0, 22), 0.5, -1)
	var fast := speed_until > now()
	_mark(holder, "ItemSpeed", "res://assets/items/shoe.png", fast, Vector2(26, 18), 0.32, 1)

func _mark(holder: Node2D, mark_name: String, path: String, shown: bool, offset: Vector2, alpha: float, z: int) -> void:
	var mark: Sprite2D = holder.get_node_or_null(mark_name)
	if not shown:
		if mark:
			mark.queue_free()
		return
	if mark == null:
		var texture := CatalogSync.texture(path)
		if texture == null:
			return
		mark = Sprite2D.new()
		mark.name = mark_name
		mark.texture = texture
		mark.scale = Vector2.ONE * (44.0 / float(texture.get_width()))
		mark.position = offset
		mark.z_index = z
		holder.add_child(mark)
	mark.modulate.a = alpha + 0.2 * sin(now() * 6.0)
