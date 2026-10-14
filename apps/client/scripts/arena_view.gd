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
var movement_cue: Dictionary = {}


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
					"life": 0.38, "duration": 0.38, "color": Color("7edff2")})
	snapshot = value
	local_id = session
	if value.get("phase") != "playing":
		movement_cue.clear()
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
			_burst(ORIGIN + Vector2(key) * CELL + Vector2.ONE * CELL / 2, Color("7edff2"), 5, 65, 0.42)
	previous_flames = flames
	if value.get("phase", "waiting") == "waiting":
		sparks.clear()
		rings.clear()
	queue_redraw()


func clear() -> void:
	snapshot = {}
	movement_cue.clear()
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
		if player.id == local_id and not movement_cue.is_empty():
			if not player.alive or target != movement_cue.origin:
				movement_cue.clear()
			elif elapsed - movement_cue.started < 0.25:
				target += movement_cue.direction * 0.25 * minf(1.0, (elapsed - movement_cue.started) / 0.05)
		var current: Vector2 = positions.get(player.id, target)
		moving[player.id] = current.distance_to(target) > 0.02
		if moving[player.id]:
			facings[player.id] = current.direction_to(target)
			if dust_timer <= 0 and player.alive:
				_burst(ORIGIN + current * CELL + Vector2(22, 38), Color("83b8ad"), 1, 10, 0.25)
		positions[player.id] = current.move_toward(target, delta * (20.0 if player.id == local_id else 14.0))
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


func movement_intent(action: String) -> void:
	if snapshot.get("phase") != "playing":
		return
	var directions := {"up": Vector2.UP, "down": Vector2.DOWN, "left": Vector2.LEFT, "right": Vector2.RIGHT}
	if not directions.has(action):
		return
	for player in snapshot.get("players", []):
		if player.id != local_id or not player.alive:
			continue
		var origin := Vector2(player.x, player.y)
		var target: Vector2 = origin + directions[action]
		if target.x < 0 or target.y < 0 or target.y >= snapshot.grid.size() or target.x >= snapshot.grid[int(target.y)].size():
			return
		if int(snapshot.grid[int(target.y)][int(target.x)]) != 0:
			return
		for bomb in snapshot.get("bombs", []):
			if Vector2(bomb.x, bomb.y) == target:
				return
		for other in snapshot.players:
			if other.id != local_id and other.alive and Vector2(other.x, other.y) == target:
				return
		if movement_cue.get("origin") == origin and movement_cue.get("action") == action:
			return
		movement_cue = {"origin": origin, "direction": directions[action], "action": action, "started": elapsed}


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


func _rounded(rect: Rect2, color: Color, radius := 8) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	draw_style_box(style, rect)


func _draw_tile(pos: Vector2, tile: int, checker: bool) -> void:
	_rounded(Rect2(pos, Vector2.ONE * CELL), Color("e7f8d7") if checker else Color("d7efc5"), 4)
	if tile == 1:
		_rounded(Rect2(pos + Vector2(3, 5), Vector2(38, 37)), Color("90b0c1"))
		_rounded(Rect2(pos + Vector2(3, 3), Vector2(38, 29)), Color("bdd6e2"))
	elif tile == 2:
		_rounded(Rect2(pos + Vector2(4, 5), Vector2(36, 37)), Color("c69758"))
		_rounded(Rect2(pos + Vector2(4, 3), Vector2(36, 12)), Color("f5d699"))
		draw_line(pos + Vector2(8, 17), pos + Vector2(30, 30), Color("fff0ce"), 2, true)


func _draw_bomb(bomb: Dictionary) -> void:
	var center := ORIGIN + Vector2(bomb.x, bomb.y) * CELL + Vector2(22, 23)
	var pulse := 17.0 + sin(elapsed * 10)
	draw_circle(center, pulse, Color("69d6ed"))
	draw_arc(center, pulse, 0, TAU, 48, Color.WHITE, 2, true)
	draw_circle(center - Vector2(5, 6), 4, Color("f2ffff"))


func _draw_flame(cell: Vector2i) -> void:
	var pos := ORIGIN + Vector2(cell) * CELL
	_rounded(Rect2(pos + Vector2.ONE, Vector2(42, 42)), Color("a1e6ed"), 12)
	draw_circle(pos + Vector2(22, 22), 16, Color("bef6fa"))


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
	Pilot.paint(self, Pilot.selected if player.id == local_id and Pilot.selected >= 0 else int(player.slot), elapsed, walking, facings.get(player.id, Vector2.DOWN),
		snapshot.get("phase") == "finished" and snapshot.get("winner") == player.id)
	draw_set_transform(Vector2.ZERO)
