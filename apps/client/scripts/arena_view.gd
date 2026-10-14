extends Node2D
## Original procedural pixel art. Animation never changes authoritative positions.

const CELL := 44.0
const ORIGIN := Vector2(50, 146)
const Pilot = preload("res://scripts/pilot_art.gd")
const COLORS = Pilot.COLORS
const MAX_PARTICLES := 420
const SPAWNS := [Vector2i(1, 1), Vector2i(13, 11), Vector2i(13, 1), Vector2i(1, 11),
	Vector2i(7, 1), Vector2i(7, 11), Vector2i(1, 7), Vector2i(13, 7)]

var snapshot: Dictionary = {}
var local_id := ""
var elapsed := 0.0
var positions: Dictionary = {}
var moving: Dictionary = {}
var sparks: Array[Dictionary] = []
var previous_flames: Dictionary = {}
var facings: Dictionary = {}
var rings: Array[Dictionary] = []
var dust_timer := 0.0


func set_snapshot(value: Dictionary, session: String) -> void:
	# Compare authoritative snapshots once; rendering never expires bombs or kills players.
	var same_round: bool = not snapshot.is_empty() and snapshot.get("round") == value.get("round")
	if not same_round:
		clear()
	if same_round:
		for old_player in snapshot.get("players", []):
			for player in value.get("players", []):
				if player.id == old_player.id and old_player.alive and not player.alive:
					var center := ORIGIN + Vector2(player.x, player.y) * CELL + Vector2(22, 22)
					_burst(center, COLORS[int(player.slot) % 8], 16, 100, 0.65)
					rings.append({"pos": center, "life": 0.5, "duration": 0.5, "color": COLORS[int(player.slot) % 8]})
		if snapshot.has("grid") and value.has("grid"):
			for y in range(13):
				for x in range(15):
					if int(snapshot.grid[y][x]) == 2 and int(value.grid[y][x]) == 0:
						_burst(ORIGIN + Vector2(x, y) * CELL + Vector2(22, 22), Color("e2ab75"), 7, 82, 0.6)
		for old_bomb in snapshot.get("bombs", []):
			var remains := false
			for bomb in value.get("bombs", []):
				if bomb.x == old_bomb.x and bomb.y == old_bomb.y:
					remains = true
			if not remains and value.get("phase") != "waiting":
				rings.append({"pos": ORIGIN + Vector2(old_bomb.x, old_bomb.y) * CELL + Vector2(22, 22),
					"life": 0.38, "duration": 0.38, "color": Color("ffd391")})
	snapshot = value
	local_id = session
	var active: Dictionary = {}
	for player in value.get("players", []):
		active[player.id] = true
		if not positions.has(player.id) or value.phase != "playing":
			positions[player.id] = Vector2(player.x, player.y)
	for id in positions.keys():
		if not active.has(id):
			positions.erase(id)
			moving.erase(id)
			facings.erase(id)
	var flames: Dictionary = {}
	for flame in value.get("flames", []):
		var key := Vector2i(flame.x, flame.y)
		flames[key] = true
		if not previous_flames.has(key):
			_burst(ORIGIN + Vector2(key) * CELL + Vector2.ONE * CELL / 2, Color("ffcd83"), 5, 65, 0.42)
	previous_flames = flames
	if value.get("phase", "waiting") == "waiting":
		sparks.clear()
		rings.clear()
	queue_redraw()


func clear() -> void:
	snapshot = {}
	positions.clear()
	moving.clear()
	facings.clear()
	sparks.clear()
	rings.clear()
	dust_timer = 0
	previous_flames.clear()
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	elapsed += delta
	dust_timer -= delta
	for player in snapshot.get("players", []):
		var target := Vector2(player.x, player.y)
		var current: Vector2 = positions.get(player.id, target)
		moving[player.id] = current.distance_to(target) > 0.02
		if moving[player.id]:
			facings[player.id] = current.direction_to(target)
			if dust_timer <= 0 and player.alive:
				_burst(ORIGIN + current * CELL + Vector2(22, 38), Color("83b8ad"), 1, 10, 0.25)
		positions[player.id] = current.move_toward(target, delta * 12.0)
	if dust_timer <= 0:
		dust_timer = 0.08
	for particle in sparks:
		particle.pos += particle.velocity * delta
		particle.velocity.y += 85 * delta
		particle.life -= delta
	sparks = sparks.filter(func(p: Dictionary): return p.life > 0)
	for ring in rings:
		ring.life -= delta
	rings = rings.filter(func(r: Dictionary): return r.life > 0)
	queue_redraw()


func _burst(center: Vector2, color: Color, count: int, speed: float, life: float) -> void:
	for i in range(mini(count, MAX_PARTICLES - sparks.size())):
		var angle := float(i) * 2.39996 + center.x * 0.13 + center.y * 0.07
		sparks.append({"pos": center, "velocity": Vector2(cos(angle), sin(angle)) * speed * (0.45 + (i % 4) * 0.18),
			"life": life, "duration": life, "color": color, "size": 2 + i % 3})


func _preview_tile(x: int, y: int) -> int:
	if x == 0 or y == 0 or x == 14 or y == 12 or (x % 2 == 0 and y % 2 == 0):
		return 1
	for spawn in SPAWNS:
		if absi(x - spawn.x) + absi(y - spawn.y) <= 2:
			return 0
	return 0 if (x * 7 + y * 11) % 5 == 0 else 2


func _draw() -> void:
	for y in range(13):
		for x in range(15):
			var tile := _preview_tile(x, y)
			if snapshot.has("grid"):
				tile = int(snapshot.grid[y][x])
			_draw_tile(ORIGIN + Vector2(x, y) * CELL, tile, (x + y) % 2 == 0)
	for flame in snapshot.get("flames", []):
		_draw_flame(Vector2i(flame.x, flame.y))
	for bomb in snapshot.get("bombs", []):
		_draw_bomb(bomb)
	var players: Array = snapshot.get("players", []).duplicate()
	players.sort_custom(func(a: Dictionary, b: Dictionary): return a.y < b.y)
	for player in players:
		_draw_player(player)
	if snapshot.is_empty():
		for i in range(3):
			_draw_player({"id": "preview" + str(i), "x": SPAWNS[i].x,
				"y": SPAWNS[i].y, "slot": i, "alive": true, "ready": false})
	for particle in sparks:
		if Rect2(ORIGIN, Vector2(660, 572)).has_point(particle.pos):
			draw_rect(Rect2(particle.pos, Vector2.ONE * particle.size), Color(particle.color, particle.life / particle.duration))
	for ring in rings:
		var progress: float = 1 - ring.life / ring.duration
		draw_arc(ring.pos, 8 + progress * 32, 0, TAU, 40, Color(ring.color, (1 - progress) * 0.75), 2, true)


func _draw_tile(pos: Vector2, tile: int, checker: bool) -> void:
	draw_rect(Rect2(pos, Vector2.ONE * CELL), Color("183c40") if checker else Color("1c4245"))
	draw_rect(Rect2(pos + Vector2(1, 1), Vector2(42, 1)), Color("244b4d"))
	if tile == 0:
		draw_rect(Rect2(pos + Vector2(3, 40), Vector2(38, 2)), Color("153639"))
		if int(pos.x + pos.y) % 7 == 0:
			draw_line(pos + Vector2(33, 36), pos + Vector2(31, 31), Color("3e7260"), 2)
			draw_line(pos + Vector2(34, 36), pos + Vector2(37, 32), Color("548268"), 2)
	if tile == 1:
		draw_rect(Rect2(pos + Vector2(2, 6), Vector2(40, 37)), Color("0b242f"))
		draw_rect(Rect2(pos + Vector2(2, 2), Vector2(40, 34)), Color("345969"))
		draw_rect(Rect2(pos + Vector2(3, 2), Vector2(38, 6)), Color("527e89"))
		draw_rect(Rect2(pos + Vector2(7, 12), Vector2(30, 17)), Color("2b4c5d"))
		draw_rect(Rect2(pos + Vector2(8, 12), Vector2(3, 13)), Color("416c79"))
		draw_rect(Rect2(pos + Vector2(16, 30), Vector2(12, 4)), Color(0.39, 0.9, 0.75, 0.12))
		draw_rect(Rect2(pos + Vector2(18, 31), Vector2(8, 2)), Color("6bb3aa"))
	elif tile == 2:
		draw_rect(Rect2(pos + Vector2(5, 9), Vector2(36, 34)), Color("112d32"))
		draw_rect(Rect2(pos + Vector2(4, 4), Vector2(35, 34)), Color("ad6f4f"))
		draw_rect(Rect2(pos + Vector2(7, 7), Vector2(29, 27)), Color("87543f"))
		for offset in [9, 20, 31]:
			draw_rect(Rect2(pos + Vector2(offset, 7), Vector2(3, 27)), Color("c4865c"))
		draw_rect(Rect2(pos + Vector2(4, 4), Vector2(35, 5)), Color("e2ab75"))
		draw_rect(Rect2(pos + Vector2(4, 30), Vector2(35, 6)), Color("c38b60"))
		for offset in [7, 32]:
			draw_rect(Rect2(pos + Vector2(offset, 5), Vector2(3, 3)), Color("6a5041"))
		draw_line(pos + Vector2(12, 11), pos + Vector2(30, 29), Color("d29a68"), 3)
		draw_rect(Rect2(pos + Vector2(17, 17), Vector2(10, 8)), Color("5e6b53"))
		draw_rect(Rect2(pos + Vector2(20, 19), Vector2(4, 4)), Color("9fce89"))


func _draw_bomb(bomb: Dictionary) -> void:
	var center := ORIGIN + Vector2(bomb.x, bomb.y) * CELL + Vector2(22, 23)
	var remaining := clampf(float(bomb.explodeAt - snapshot.now) / 2000.0, 0, 1)
	var pulse := 1.0 + sin(elapsed * (10 + (1 - remaining) * 10)) * 0.055
	draw_circle(center + Vector2(1, 7), 16, Color(0, 0, 0, 0.22))
	draw_circle(center, 18 * pulse, Color(1, 0.55, 0.39, 0.12))
	draw_circle(center, 13 * pulse, Color("101e31"))
	draw_circle(center - Vector2(3, 3), 9 * pulse, Color("314257"))
	draw_rect(Rect2(center + Vector2(-8, -5), Vector2(16, 10)), Color("f29074"))
	draw_rect(Rect2(center + Vector2(-3, -8), Vector2(6, 16)), Color("f29074"))
	draw_rect(Rect2(center + Vector2(-2, -3), Vector2(4, 6)), Color("ffd39b"))
	draw_line(center + Vector2(3, -12), center + Vector2(7, -18), Color("d5b986"), 3)
	var spark := center + Vector2(7, -18)
	draw_circle(spark, 3 + sin(elapsed * 18), Color("ffe6a8"))
	for i in range(3):
		var drift := fmod(elapsed * 2.5 + i * 0.33, 1.0)
		draw_circle(spark + Vector2(sin(i * 4.0 + elapsed) * drift * 9, -drift * 17), 2 * (1 - drift), Color(1, 0.8, 0.5, 1 - drift))
	draw_arc(center, 17, -PI / 2, -PI / 2 + TAU * remaining, 28, Color("ffd78a"), 2, true)


func _draw_flame(cell: Vector2i) -> void:
	var center := ORIGIN + Vector2(cell) * CELL + Vector2(22, 22)
	var shimmer := sin(elapsed * 20 + cell.x + cell.y) * 2
	draw_circle(center, 25, Color(1, 0.52, 0.2, 0.15))
	# Join only cells that are actually burning; end caps respect blocked blast paths.
	for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if previous_flames.has(cell + direction):
			var endpoint: Vector2 = center + Vector2(direction) * 23
			draw_line(center, endpoint, Color("f37455"), 27 + shimmer)
			draw_line(center, endpoint, Color("ffbf69"), 17 + shimmer)
			draw_line(center, endpoint, Color("fff0b5"), 7)
	draw_circle(center, 15 + shimmer, Color("ffad60"))
	draw_circle(center, 10 + shimmer, Color("ffdb86"))
	draw_rect(Rect2(center - Vector2(5, 5), Vector2(10, 10)), Color("fff6d7"))


func _draw_player(player: Dictionary) -> void:
	var color: Color = COLORS[int(player.slot) % COLORS.size()]
	var cell: Vector2 = positions.get(player.id, Vector2(player.x, player.y))
	var pos := ORIGIN + cell * CELL
	if not player.alive:
		draw_arc(pos + Vector2(22, 30), 12, 0, TAU, 24, Color(color, 0.25), 1, true)
		draw_circle(pos + Vector2(22, 24 + sin(elapsed * 3) * 2), 6, Color(color, 0.18))
		draw_circle(pos + Vector2(20, 23 + sin(elapsed * 3) * 2), 1, Color(color, 0.55))
		draw_circle(pos + Vector2(24, 23 + sin(elapsed * 3) * 2), 1, Color(color, 0.55))
		return
	var walking: bool = moving.get(player.id, false)
	draw_set_transform(pos + Vector2(22, 37), 0, Vector2(1, 0.3))
	draw_circle(Vector2.ZERO, 16, Color(0, 0, 0, 0.3))
	if player.id == local_id:
		draw_arc(Vector2.ZERO, 20, 0, TAU, 32, Color(color, 0.8), 2, true)
	draw_set_transform(pos)
	if player.id == local_id:
		draw_colored_polygon(PackedVector2Array([Vector2(18, -10), Vector2(26, -10), Vector2(22, -5)]), color)
	Pilot.paint(self, int(player.slot), elapsed, walking, facings.get(player.id, Vector2.DOWN),
		snapshot.get("phase") == "finished" and snapshot.get("winner") == player.id)
	draw_set_transform(Vector2.ZERO)
