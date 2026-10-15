extends Node2D
## Game Boom step 3 - single-player arcade arena, three levels, procedural audio,
## six-frame movement and pathfinding bot AI. All assets custom-generated.

const TILE: int = 64
const COLUMNS: int = 15
const ROWS: int = 11
const START_TIME: float = 180.0
const ARENA_POS: Vector2 = Vector2(160, 112)
const HEROES = ["bombo", "mimi", "zin", "lala", "kai"]
const HERO_NAMES = ["BOMBO", "MIMI", "ZIN", "LALA", "KAI"]
const HERO_COLORS = [Color("2baaff"), Color("ff6da9"), Color("ff6959"), Color("ffbe3c"), Color("5cdc90")]
const LEVEL_FILES = ["res://levels/park.json", "res://levels/frost.json", "res://levels/coast.json"]
const DIRECTIONS = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const HERO_SCRIPT = preload("res://scripts/hero_sprite.gd")

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var selected_hero: int = 0
var selected_level: int = 0
var current_level: Dictionary = {}
var game_state: String = "menu"
var elapsed: float = 0.0
var remaining: float = START_TIME
var player_move_cooldown: float = 0.0
var world: Node2D
var ui_layer: CanvasLayer
var hud: Control
var menu: Control
var result: Control
var menu_cards: Array = []
var level_cards: Array = []
var hud_title: Label
var hud_stats: Label
var hud_timer: Label
var hud_status: Label
var result_title: Label
var result_detail: Label
var continue_button: Button
var audio_players: Array = []
var next_audio: int = 0
var music: AudioStreamPlayer
var music_enabled: bool = true
var terrain: Dictionary = {}  # Vector2i -> Sprite2D
var crates: Dictionary = {}  # Vector2i -> Sprite2D
var items: Dictionary = {}  # Vector2i -> {node, kind}
var bombs: Array = []  # {cell, owner, node, timer, range, ticked}
var bursts: Array = []  # {cells, visuals, duration}
var fighters: Array = []  # {cell, sprite, root, alive, bot, ...}
var player: Dictionary = {}
var score: int = 0
var remaining_bots: int = 0
var status_message: String = ""
var status_timeout: float = 0.0
var explosion_depth: int = 0


func _ready() -> void:
	rng.seed = 20261015
	var background = Sprite2D.new()
	background.texture = load("res://assets/backdrop.png")
	background.position = Vector2(640, 460)
	background.z_index = -20
	add_child(background)
	_create_audio()
	_create_ui()
	_show_menu()
	print("PRACTICE_READY")


func _create_audio() -> void:
	for i in range(10):
		var track = AudioStreamPlayer.new()
		track.name = "SFX_%02d" % i
		track.volume_db = -7.0
		add_child(track)
		audio_players.append(track)
	music = AudioStreamPlayer.new()
	music.name = "OriginalMusic"
	music.stream = load("res://assets/audio/music_loop.wav")
	music.volume_db = -22.0
	music.finished.connect(_restart_music)
	add_child(music)
	if music_enabled:
		music.play()


func _restart_music() -> void:
	if music_enabled:
		music.play()


func _sound(sound_id: String) -> void:
	if not music_enabled:
		return
	var path = "res://assets/audio/%s.wav" % sound_id
	if not ResourceLoader.exists(path):
		return
	var track: AudioStreamPlayer = audio_players[next_audio]
	next_audio = (next_audio + 1) % audio_players.size()
	track.stop()
	track.stream = load(path)
	track.play()


func _toggle_audio() -> void:
	music_enabled = not music_enabled
	if music_enabled:
		music.play()
		_flash_status("Âm thanh: BẬT")
	else:
		music.stop()
		for track in audio_players:
			track.stop()
		_flash_status("Âm thanh: TẮT")


func _create_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 15
	add_child(ui_layer)
	hud = Control.new()
	hud.size = Vector2(1280, 920)
	ui_layer.add_child(hud)
	_panel(hud, Vector2(160, 10), Vector2(960, 87), Color("113f6b"), Color("5ad3ff"))
	hud_title = _label(hud, "BỤP BỤP!", Vector2(183, 13), Vector2(240, 73), 19, Color("fff0a3"))
	hud_stats = _label(hud, "", Vector2(432, 24), Vector2(460, 40), 17, Color.WHITE)
	hud_timer = _label(hud, "", Vector2(926, 22), Vector2(173, 42), 27, Color("fff0a3"), true)
	_panel(hud, Vector2(160, 835), Vector2(960, 70), Color("123959"), Color("376c91"))
	hud_status = _label(hud, "", Vector2(175, 842), Vector2(924, 50), 17, Color("d0f2ff"), true)
	_label(hud, "DI CHUYỂN\nW A S D\nHOẶC\nPHÍM MŨI TÊN", Vector2(12, 296), Vector2(136, 190), 18, Color("c9f4ff"), true)
	_label(hud, "ĐẶT BOM\n[ SPACE ]\n\nR: CHƠI LẠI\nM: ÂM THANH\nESC: TẠM DỪNG", Vector2(1130, 290), Vector2(145, 210), 16, Color("fff0c8"), true)
	_label(hud, "PHÁ THÙNG\nNHẶT VẬT PHẨM\nHẠ 3 ĐỐI THỦ", Vector2(8, 730), Vector2(143, 85), 15, Color("fce4a8"), true)
	hud.hide()

	menu = Control.new()
	menu.size = Vector2(1280, 920)
	ui_layer.add_child(menu)
	_panel(menu, Vector2(105, 55), Vector2(1070, 790), Color("0e365d"), Color("57d4ff"))
	_label(menu, "BỤP BỤP!", Vector2(260, 66), Vector2(760, 78), 57, Color("ffe17b"), true)
	_label(menu, "SÂN CHƠI BOM NƯỚC  •  CHỌN NHÂN VẬT VÀ BẢN ĐỒ", Vector2(258, 147), Vector2(764, 36), 22, Color("b8efff"), true)
	_label(menu, "CHỌN NHÂN VẬT", Vector2(390, 196), Vector2(500, 39), 23, Color.WHITE, true)
	for i in range(HEROES.size()):
		var card = _panel(menu, Vector2(158 + i * 195, 238), Vector2(184, 205), Color("18527d"), HERO_COLORS[i])
		var portrait = TextureRect.new()
		portrait.texture = load("res://assets/characters/portraits/%s.png" % HEROES[i])
		portrait.position = Vector2(22, 7)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.size = Vector2(140, 123)
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(portrait)
		_label(card, HERO_NAMES[i], Vector2(7, 128), Vector2(170, 27), 20, Color.WHITE, true)
		var b = _button(card, "CHỌN", Vector2(23, 161), Vector2(138, 33), HERO_COLORS[i])
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(_select_hero.bind(i))
		menu_cards.append({"card":card,"button":b})
	_label(menu, "CHỌN BẢN ĐỒ", Vector2(400, 457), Vector2(480, 36), 23, Color.WHITE, true)
	var ids = ["park", "frost", "coast"]
	var names = ["CÔNG VIÊN KẸO", "LÂU ĐÀI BĂNG", "ĐẢO NẮNG VÀNG"]
	var colors = [Color("7ddd72"), Color("72d8fc"), Color("ffd073")]
	for i in range(ids.size()):
		var card = _panel(menu, Vector2(153 + i * 333, 501), Vector2(316, 146), Color("18527d"), colors[i])
		var preview = TextureRect.new()
		preview.texture = load("res://assets/level_previews/%s.png" % ids[i])
		preview.position = Vector2(10, 9)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.size = Vector2(152, 112)
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(preview)
		_label(card, names[i], Vector2(167, 11), Vector2(141, 51), 17, Color.WHITE, true)
		var b = _button(card, "CHỌN MAP", Vector2(170, 79), Vector2(132, 42), colors[i])
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(_select_level.bind(i))
		level_cards.append({"button": b})
	_button(menu, "BẮT ĐẦU CHƠI", Vector2(451, 676), Vector2(377, 74), Color("ffac2f")).pressed.connect(_new_round)
	_label(menu, "5 NHÂN VẬT  •  3 BẢN ĐỒ  •  ÂM THANH TỰ TẠO  •  BOT NÉ BOM", Vector2(163, 770), Vector2(953, 29), 16, Color("a7cee4"), true)
	_button(menu, "CỬA HÀNG / TRANG BỊ", Vector2(451, 808), Vector2(377, 34), Color("34b9dc")).pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/ui/ui_showcase.tscn"))
	_select_hero(maxi(0, HEROES.find(str(UIState.profile.get("selected_character", "bombo")))))
	_select_level(0)

	result = Control.new()
	result.size = Vector2(1280, 920)
	ui_layer.add_child(result)
	var shade = ColorRect.new()
	shade.color = Color(0.01, 0.08, 0.20, 0.80)
	shade.size = Vector2(1280, 920)
	result.add_child(shade)
	_panel(result, Vector2(352, 224), Vector2(576, 457), Color("104269"), Color("ffe28c"))
	result_title = _label(result, "", Vector2(373, 284), Vector2(534, 85), 44, Color("ffe18b"), true)
	result_detail = _label(result, "", Vector2(380, 390), Vector2(521, 95), 21, Color.WHITE, true)
	_button(result, "CHƠI LẠI", Vector2(400, 544), Vector2(225, 68), Color("ffb239")).pressed.connect(_new_round)
	_button(result, "MENU", Vector2(654, 544), Vector2(225, 68), Color("34b9dc")).pressed.connect(_show_menu)
	continue_button = _button(result, "TIẾP TỤC", Vector2(509, 624), Vector2(263, 45), Color("89df9a"))
	continue_button.pressed.connect(_resume_game)
	result.hide()


func _select_hero(index: int) -> void:
	selected_hero = index
	UIState.choose_hero(HEROES[index])
	for i in range(menu_cards.size()):
		var button: Button = menu_cards[i]["button"]
		button.text = "ĐÃ CHỌN" if i == index else "CHỌN"
		button.disabled = i == index


func _select_level(index: int) -> void:
	selected_level = index
	for i in range(level_cards.size()):
		var button: Button = level_cards[i]["button"]
		button.text = "ĐÃ CHỌN" if i == index else "CHỌN MAP"
		button.disabled = i == index
	_sound("ui_select")


func _show_menu() -> void:
	game_state = "menu"
	if is_instance_valid(world):
		world.hide()
	hud.hide()
	result.hide()
	menu.show()


func _load_level() -> bool:
	var json_text: String = FileAccess.get_file_as_string(LEVEL_FILES[selected_level])
	var parsed = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Level JSON không hợp lệ: " + LEVEL_FILES[selected_level])
		return false
	current_level = parsed
	if current_level.get("layout", []).size() != ROWS:
		push_error("Sai số hàng trong bản đồ.")
		return false
	for row in current_level["layout"]:
		if str(row).length() != COLUMNS:
			push_error("Sai số cột trong bản đồ.")
			return false
	return true


func _new_round() -> void:
	if not _load_level():
		return
	if is_instance_valid(world):
		world.hide()
		world.queue_free()
	terrain.clear()
	crates.clear()
	items.clear()
	bombs.clear()
	bursts.clear()
	fighters.clear()
	player = {}
	rng.seed = 20261015 + selected_level * 973
	remaining = START_TIME
	elapsed = 0.0
	player_move_cooldown = 0.0
	score = 0
	status_message = "Phá thùng, nhặt vật phẩm và đánh bại 3 đối thủ!"
	status_timeout = 4.0
	world = Node2D.new()
	world.name = "Arena_%s" % current_level["id"]
	world.position = ARENA_POS
	add_child(world)
	_build_map()
	player = _spawn_fighter(HEROES[selected_hero], Vector2i(1, 1), false)
	var enemy_names: Array = HEROES.duplicate()
	enemy_names.erase(HEROES[selected_hero])
	_spawn_fighter(enemy_names[0], Vector2i(13, 1), true)
	_spawn_fighter(enemy_names[1], Vector2i(13, 9), true)
	_spawn_fighter(enemy_names[2], Vector2i(1, 9), true)
	remaining_bots = 3
	_update_hud()
	game_state = "playing"
	menu.hide()
	result.hide()
	hud.show()
	_sound("round_start")
	print("PRACTICE_ROUND_STARTED ", current_level["id"])


func _build_map() -> void:
	var floor_layer = Node2D.new()
	floor_layer.z_index = -5
	floor_layer.name = "Floor"
	world.add_child(floor_layer)
	var obstacles = Node2D.new()
	obstacles.z_index = 3
	obstacles.name = "Obstacles"
	world.add_child(obstacles)
	var floor_theme: String = str(current_level["theme"])
	var wall_name: String = str(current_level["wall"])
	var crate_name: String = str(current_level["crate"])
	var floors: Array = []
	for n in range(2):
		for m in range(4):
			floors.append(load("res://assets/tiles/%s/%d_%d.png" % [floor_theme, n, m]))
	var wall_tex = load("res://assets/obstacles/%s/00.png" % wall_name)
	var crate_tex = load("res://assets/obstacles/%s/00.png" % crate_name)
	for y in range(ROWS):
		var line: String = str(current_level["layout"][y])
		for x in range(COLUMNS):
			var cell = Vector2i(x, y)
			var ground = Sprite2D.new()
			ground.texture = floors[(y % 2) * 4 + ((x + y) % 4)]
			ground.position = _cell_center(cell)
			floor_layer.add_child(ground)
			if line.substr(x, 1) == "#":
				var wall = Sprite2D.new()
				wall.texture = wall_tex
				wall.position = _cell_center(cell)
				obstacles.add_child(wall)
				terrain[cell] = wall
			elif line.substr(x, 1) == "C":
				var crate = Sprite2D.new()
				crate.texture = crate_tex
				crate.position = _cell_center(cell)
				obstacles.add_child(crate)
				crates[cell] = crate
	var border = ReferenceRect.new()
	border.editor_only = false
	border.position = Vector2.ZERO
	border.size = Vector2(COLUMNS * TILE, ROWS * TILE)
	border.border_color = Color("d2f7ff")
	border.border_width = 3
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.add_child(border)


func _spawn_fighter(hero_id: String, start_cell: Vector2i, is_bot: bool) -> Dictionary:
	var holder = Node2D.new()
	holder.name = "Bot_%s" % hero_id if is_bot else "Player"
	holder.position = _cell_center(start_cell)
	holder.z_index = 7
	world.add_child(holder)
	var shadow = Polygon2D.new()
	var points = PackedVector2Array()
	for j in range(18):
		var angle: float = TAU * float(j) / 18.0
		points.append(Vector2(cos(angle) * 18.0, sin(angle) * 6.0) + Vector2(0, 24))
	shadow.polygon = points
	shadow.color = Color(0.01, 0.16, 0.29, 0.40)
	holder.add_child(shadow)
	var visual = HERO_SCRIPT.new()
	holder.add_child(visual)
	visual.configure(hero_id)
	var fighter = {
		"hero":hero_id,"cell":start_cell,"bot":is_bot,"alive":true,
		"lives":1 if is_bot else 3,"bomb_capacity":1,"bomb_range":2,
		"speed":1.0,"invulnerable":0.0,"action_time":0.0,"walk_time":0.0,
		"bomb_clock":1.7 + rng.randf_range(0.0, 1.8),
		"ai_clock":rng.randf_range(0.2, 0.8),
		"root":holder,"sprite":visual
	}
	fighters.append(fighter)
	return fighter


func _process(delta: float) -> void:
	if game_state != "playing":
		return
	elapsed += delta
	remaining = maxf(0.0, remaining - delta)
	player_move_cooldown = maxf(0.0, player_move_cooldown - delta)
	status_timeout = maxf(0.0, status_timeout - delta)
	_update_actor_timers(delta)
	_update_player_input()
	_update_bots(delta)
	_update_bombs(delta)
	_update_bursts(delta)
	_resolve_outcome()
	_update_hud()
	if remaining <= 0.0:
		_finish(false)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key: InputEventKey = event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_M:
		_toggle_audio()
		return
	if key.keycode == KEY_ESCAPE:
		if game_state == "playing":
			game_state = "paused"
			result_title.text = "TẠM DỪNG"
			result_detail.text = "Nhấn ESC hoặc TIẾP TỤC để chơi tiếp."
			continue_button.show()
			result.show()
		elif game_state == "paused":
			_resume_game()
		return
	if key.keycode == KEY_R and game_state in ["playing", "paused", "ended"]:
		_new_round()
		return
	if game_state != "playing":
		return
	if key.keycode == KEY_SPACE:
		_place_bomb(player)


func _resume_game() -> void:
	if game_state == "paused":
		game_state = "playing"
		result.hide()


func _update_player_input() -> void:
	if player.is_empty() or not player["alive"]:
		return
	var direction = Vector2i.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		direction = Vector2i.LEFT
	elif Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		direction = Vector2i.RIGHT
	elif Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		direction = Vector2i.UP
	elif Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		direction = Vector2i.DOWN
	if direction != Vector2i.ZERO and player_move_cooldown <= 0.0:
		player_move_cooldown = 0.155 / float(player["speed"])
		if _move_fighter(player, direction):
			_sound("footstep")
	elif direction == Vector2i.ZERO and player["action_time"] <= 0.0 and player["walk_time"] <= 0.0:
		player["sprite"].action("idle")


func _update_actor_timers(delta: float) -> void:
	for actor in fighters:
		if not actor["alive"]:
			continue
		actor["invulnerable"] = maxf(0.0, float(actor["invulnerable"]) - delta)
		actor["action_time"] = maxf(0.0, float(actor["action_time"]) - delta)
		actor["walk_time"] = maxf(0.0, float(actor["walk_time"]) - delta)
		if actor["bot"]:
			actor["bomb_clock"] = maxf(0.0, float(actor["bomb_clock"]) - delta)
		if actor["walk_time"] <= 0.0 and actor["action_time"] <= 0.0:
			actor["sprite"].action("idle")
		var actor_root: Node2D = actor["root"]
		actor_root.modulate.a = 0.52 if actor["invulnerable"] > 0.0 and int(elapsed * 12.0) % 2 == 0 else 1.0


func _update_bots(delta: float) -> void:
	for actor in fighters:
		if not actor["bot"] or not actor["alive"]:
			continue
		actor["ai_clock"] -= delta
		if actor["ai_clock"] > 0.0:
			continue
		var step_time: float = float(current_level["bot_step"])
		actor["ai_clock"] = step_time + rng.randf_range(0.01, 0.08)
		var now: Vector2i = actor["cell"]
		# Bots react to the explosion forecast, not only already visible flames.
		if _danger_at(now, 2.0):
			var escape = _escape_step(actor)
			if escape != Vector2i.ZERO:
				_move_fighter(actor, escape)
			continue
		if actor["bomb_clock"] <= 0.0 and _should_place_bot_bomb(actor) and _has_escape_route(actor):
			_place_bomb(actor)
			actor["bomb_clock"] = float(current_level["bot_bomb"]) + rng.randf_range(0.1, 1.0)
			var flee = _escape_step(actor)
			if flee != Vector2i.ZERO:
				_move_fighter(actor, flee)
			continue
		var roam = _roam_step(actor)
		if roam != Vector2i.ZERO:
			_move_fighter(actor, roam)


func _should_place_bot_bomb(actor: Dictionary) -> bool:
	var pos: Vector2i = actor["cell"]
	for direction in DIRECTIONS:
		if crates.has(pos + direction):
			return true
	var blast: Array = _blast_cells(pos, int(actor["bomb_range"]))
	for rival in fighters:
		if rival != actor and rival["alive"] and rival["cell"] in blast:
			return true
	return false


func _predicted_bombs() -> Array:
	var forecast: Array = []
	for bomb in bombs:
		forecast.append({"cells": _blast_cells(bomb["cell"], int(bomb["range"])), "cell": bomb["cell"], "time": float(bomb["timer"])})
	# Propagate earlier fuses through the full chain, including reverse placement order.
	for _pass in range(forecast.size()):
		var changed := false
		for source in forecast:
			for target in forecast:
				if target["cell"] in source["cells"] and target["time"] > source["time"]:
					target["time"] = source["time"]
					changed = true
		if not changed:
			break
	return forecast


func _danger_at(cell: Vector2i, within_seconds: float = 2.0) -> bool:
	for burst in bursts:
		if cell in burst["cells"]:
			return true
	for predicted in _predicted_bombs():
		if predicted["time"] <= within_seconds and cell in predicted["cells"]:
			return true
	return false


func _safe_path_cell(cell: Vector2i, arrival: float) -> bool:
	# Do not route through live flames or through a blast that fires before arrival.
	for burst in bursts:
		if cell in burst["cells"]:
			return false
	return not _danger_at(cell, arrival + 0.15)


func _has_escape_route(actor: Dictionary) -> bool:
	# Before planting a bomb, BFS through passable cells to find a tile that
	# will survive the actor's own cross-shaped blast (within four steps).
	var start: Vector2i = actor["cell"]
	var mine: Array = _blast_cells(start, int(actor["bomb_range"]))
	var queue: Array = [{"cell":start,"depth":0}]
	var seen: Dictionary = {}
	seen[start] = true
	while not queue.is_empty():
		var state: Dictionary = queue.pop_front()
		var cell: Vector2i = state["cell"]
		var depth: int = state["depth"]
		if depth > 0 and not (cell in mine) and not _danger_at(cell, 2.0):
			return true
		if depth >= 4:
			continue
		for d in DIRECTIONS:
			var target: Vector2i = cell + d
			if not seen.has(target) and _can_walk(target) and _safe_path_cell(target, (depth + 1) * (float(current_level["bot_step"]) + 0.08)):
				seen[target] = true
				queue.append({"cell":target,"depth":depth+1})
	return false


func _escape_step(actor: Dictionary) -> Vector2i:
	var start: Vector2i = actor["cell"]
	var queue: Array = [{"cell":start,"step":Vector2i.ZERO,"depth":0}]
	var seen: Dictionary = {}
	seen[start] = true
	while not queue.is_empty():
		var state: Dictionary = queue.pop_front()
		var cell: Vector2i = state["cell"]
		var depth: int = state["depth"]
		if depth > 0 and not _danger_at(cell, 3.0):
			return state["step"]
		if depth >= 7:
			continue
		var shuffled: Array = DIRECTIONS.duplicate()
		shuffled.shuffle()
		for d in shuffled:
			var target: Vector2i = cell + d
			if not seen.has(target) and _can_walk(target) and _safe_path_cell(target, (depth + 1) * (float(current_level["bot_step"]) + 0.08)):
				seen[target] = true
				var first: Vector2i = d if depth == 0 else state["step"]
				queue.append({"cell":target,"step":first,"depth":depth+1})
	# Don't move into immediately exploding cells when no safe route exists.
	for d in DIRECTIONS:
		if _can_walk(start + d) and not _danger_at(start + d, 0.65):
			return d
	return Vector2i.ZERO


func _roam_step(actor: Dictionary) -> Vector2i:
	# Find an inexpensive reachable tile for attacking crates, collecting an
	# item or lining up a water-bomb with a rival; never walk into near blasts.
	var start: Vector2i = actor["cell"]
	var queue: Array = [{"cell":start,"step":Vector2i.ZERO,"depth":0}]
	var seen: Dictionary = {}
	seen[start] = true
	var best_score: float = 99999.0
	var best_step: Vector2i = Vector2i.ZERO
	while not queue.is_empty():
		var state: Dictionary = queue.pop_front()
		var cell: Vector2i = state["cell"]
		var depth: int = state["depth"]
		if not _danger_at(cell, 1.4):
			var quality: float = float(depth) * 0.65
			var nearest: int = 99
			for rival in fighters:
				if rival != actor and rival["alive"]:
					nearest = mini(nearest, _distance(cell, rival["cell"]))
			quality += nearest * 1.2
			if items.has(cell):
				quality -= 12.0
			for d in DIRECTIONS:
				if crates.has(cell + d):
					quality -= 7.0
					break
			if depth == 0:
				quality += 5.0
			quality += rng.randf_range(0.0, 1.4)
			if quality < best_score:
				best_score = quality
				best_step = state["step"]
		if depth >= 11:
			continue
		var shuffled: Array = DIRECTIONS.duplicate()
		shuffled.shuffle()
		for d in shuffled:
			var target: Vector2i = cell + d
			if not seen.has(target) and _can_walk(target) and _safe_path_cell(target, (depth + 1) * (float(current_level["bot_step"]) + 0.08)):
				seen[target] = true
				var first: Vector2i = d if depth == 0 else state["step"]
				queue.append({"cell":target,"step":first,"depth":depth+1})
	return best_step


func _distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func _can_walk(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= COLUMNS or cell.y >= ROWS:
		return false
	if terrain.has(cell) or crates.has(cell):
		return false
	for bomb in bombs:
		if bomb["cell"] == cell:
			return false
	for actor in fighters:
		if actor["alive"] and actor["cell"] == cell:
			return false
	return true


func _move_fighter(actor: Dictionary, direction: Vector2i) -> bool:
	if not actor["alive"] or direction == Vector2i.ZERO:
		return false
	var target: Vector2i = actor["cell"] + direction
	if not _can_walk(target):
		return false
	actor["cell"] = target
	actor["walk_time"] = 0.16
	var holder: Node2D = actor["root"]
	# Existing movement tween is cancelled to avoid fighting over position.
	if actor.has("travel") and is_instance_valid(actor["travel"]):
		actor["travel"].kill()
	var travel: Tween = holder.create_tween()
	actor["travel"] = travel
	travel.set_trans(Tween.TRANS_SINE)
	travel.set_ease(Tween.EASE_OUT)
	travel.tween_property(holder, "position", _cell_center(target), minf(0.14, 0.14 / float(actor["speed"])))
	if actor["action_time"] <= 0.0:
		var action: String = "walk_down"
		if direction == Vector2i.UP:
			action = "walk_up"
		elif direction == Vector2i.LEFT:
			action = "walk_left"
		elif direction == Vector2i.RIGHT:
			action = "walk_right"
		actor["sprite"].action(action)
	_collect_item(actor)
	for burst in bursts:
		if target in burst["cells"]:
			_hit_fighter(actor)
			break
	return true


func _place_bomb(actor: Dictionary) -> void:
	if not actor["alive"]:
		return
	var active_count: int = 0
	for b in bombs:
		if b["owner"] == actor:
			active_count += 1
		if b["cell"] == actor["cell"]:
			return
	if active_count >= actor["bomb_capacity"]:
		return
	var sprite = Sprite2D.new()
	sprite.texture = load("res://assets/bombs/%s.png" % current_level["bomb"])
	sprite.position = _cell_center(actor["cell"])
	sprite.scale = Vector2(0.68, 0.68)
	sprite.z_index = 5
	world.add_child(sprite)
	bombs.append({
		"owner":actor,"cell":actor["cell"],"timer":2.4,
		"range":actor["bomb_range"],"node":sprite,"ticked":false
	})
	actor["sprite"].action("place_bomb")
	actor["action_time"] = 0.30
	_sound("place_bomb")


func _update_bombs(delta: float) -> void:
	# Finish only after every due bomb in this frame has applied its damage.
	explosion_depth += 1
	for bomb in bombs.duplicate():
		if not bombs.has(bomb):
			continue
		bomb["timer"] -= delta
		var pulse: float = 0.65 + 0.045 * sin(elapsed * (11.0 + 2.0 / maxf(float(bomb["timer"]), 0.25)))
		bomb["node"].scale = Vector2(pulse, pulse)
		if bomb["timer"] < 0.55 and not bomb["ticked"]:
			bomb["ticked"] = true
			_sound("bomb_tick")
		if bomb["timer"] <= 0.0:
			_explode_bomb(bomb)
	explosion_depth -= 1
	_resolve_outcome()


func _blast_cells(origin: Vector2i, power: int) -> Array:
	var affected: Array = [origin]
	for direction in DIRECTIONS:
		for step in range(1, power + 1):
			var target: Vector2i = origin + direction * step
			if target.x < 0 or target.y < 0 or target.x >= COLUMNS or target.y >= ROWS:
				break
			if terrain.has(target):
				break
			affected.append(target)
			if crates.has(target):
				break
			# Bom khác chặn luồng để kích hoạt phản ứng dây chuyền.
			var hit_bomb: bool = false
			for other in bombs:
				if other["cell"] == target:
					hit_bomb = true
					break
			if hit_bomb:
				break
	return affected


func _explode_bomb(bomb: Dictionary) -> void:
	if not bombs.has(bomb):
		return
	explosion_depth += 1
	var affected: Array = _blast_cells(bomb["cell"], int(bomb["range"]))
	bombs.erase(bomb)
	if is_instance_valid(bomb["node"]):
		bomb["node"].queue_free()
	var chained: Array = []
	for cell in affected:
		if crates.has(cell):
			crates[cell].queue_free()
			crates.erase(cell)
			score += 10
			_drop_item(cell)
		for other in bombs:
			if other["cell"] == cell and not chained.has(other):
				chained.append(other)
	var vfx: Array = []
	var effect_key: String = str(current_level["fx"])
	var count: int = 6 if effect_key == "water_splash" else 8
	for cell in affected:
		var splash = AnimatedSprite2D.new()
		var fx = SpriteFrames.new()
		fx.remove_animation("default")
		fx.add_animation("blast")
		fx.set_animation_speed("blast", 15.0)
		for n in range(count):
			fx.add_frame("blast", load("res://assets/effects/%s/%02d.png" % [effect_key, n]))
		splash.sprite_frames = fx
		splash.position = _cell_center(cell)
		splash.scale = Vector2(0.80, 0.80)
		splash.z_index = 11
		world.add_child(splash)
		splash.play("blast")
		vfx.append(splash)
	bursts.append({"cells":affected,"visuals":vfx,"duration":0.52})
	_sound("explosion")
	for actor in fighters:
		if actor["alive"] and actor["cell"] in affected:
			_hit_fighter(actor)
	for other in chained:
		if bombs.has(other):
			_explode_bomb(other)
	explosion_depth -= 1
	if explosion_depth == 0:
		_resolve_outcome()


func _update_bursts(delta: float) -> void:
	for burst in bursts.duplicate():
		burst["duration"] -= delta
		if burst["duration"] <= 0.0:
			bursts.erase(burst)
			for visual in burst["visuals"]:
				if is_instance_valid(visual):
					visual.queue_free()


func _hit_fighter(actor: Dictionary) -> void:
	if not actor["alive"] or actor["invulnerable"] > 0.0:
		return
	actor["lives"] -= 1
	actor["sprite"].action("hit")
	actor["action_time"] = 0.47
	actor["invulnerable"] = 1.65
	_sound("hit")
	if actor["lives"] <= 0:
		actor["alive"] = false
		actor["sprite"].action("lose")
		actor["root"].modulate = Color(1.0, 1.0, 1.0, 0.72)
		if actor["bot"]:
			remaining_bots -= 1
			score += 100
			_flash_status("Hạ đối thủ! Còn %d bot." % remaining_bots)

	elif not actor["bot"]:
		_flash_status("Bạn trúng bom! Còn %d tim." % int(actor["lives"]))


func _resolve_outcome() -> void:
	# Resolve after every victim in a chain; death takes priority over a final bot kill.
	if player.is_empty() or game_state != "playing":
		return
	if not player["alive"]:
		_finish(false)
	elif remaining_bots == 0:
		_finish(true)


func _drop_item(cell: Vector2i) -> void:
	if rng.randf() > 0.43 or items.has(cell):
		return
	var kind: String = ["extra_bomb", "flame", "shoe"][rng.randi_range(0, 2)]
	var sprite = Sprite2D.new()
	sprite.texture = load("res://assets/items/%s.png" % kind)
	sprite.position = _cell_center(cell)
	sprite.scale = Vector2(0.67, 0.67)
	sprite.z_index = 5
	world.add_child(sprite)
	items[cell] = {"node":sprite,"kind":kind}


func _collect_item(actor: Dictionary) -> void:
	if not items.has(actor["cell"]):
		return
	var drop: Dictionary = items[actor["cell"]]
	match drop["kind"]:
		"extra_bomb":
			actor["bomb_capacity"] = mini(5, int(actor["bomb_capacity"]) + 1)
			if not actor["bot"]:
				_flash_status("+1 bom được đặt cùng lúc!")
		"flame":
			actor["bomb_range"] = mini(6, int(actor["bomb_range"]) + 1)
			if not actor["bot"]:
				_flash_status("+1 tầm nổ bom!")
		"shoe":
			actor["speed"] = minf(2.0, float(actor["speed"]) + 0.18)
			if not actor["bot"]:
				_flash_status("Tăng tốc độ di chuyển!")
	drop["node"].queue_free()
	items.erase(actor["cell"])
	_sound("collect")
	if not actor["bot"]:
		score += 25


func _flash_status(message: String) -> void:
	status_message = message
	status_timeout = 3.1


func _update_hud() -> void:
	if player.is_empty():
		return
	hud_title.text = "BỤP BỤP!\n%s" % str(current_level["name"])
	var hearts: String = "TIM %d/3" % int(player["lives"])
	hud_stats.text = "%s    BOM %d    TẦM %d    ĐIỂM %d    BOT %d" % [
		hearts, int(player["bomb_capacity"]), int(player["bomb_range"]), score, remaining_bots
	]
	var seconds: int = int(ceil(remaining))
	hud_timer.text = "%02d:%02d" % [int(seconds / 60), seconds % 60]
	if status_timeout > 0.0:
		hud_status.text = status_message
	else:
		hud_status.text = "WASD / MŨI TÊN: DI CHUYỂN   •   SPACE: BOM   •   R: CHƠI LẠI   •   M: ÂM THANH   •   ESC: TẠM DỪNG"


func _finish(won: bool) -> void:
	if game_state != "playing":
		return
	game_state = "ended"
	result.show()
	continue_button.hide()
	result_title.text = "CHIẾN THẮNG!" if won else "THUA RỒI!"
	if won:
		player["sprite"].action("win")
		_sound("victory")
	else:
		if player["alive"]:
			player["sprite"].action("lose")
		_sound("defeat")
	result_detail.text = "Map: %s\nĐiểm: %d      Thời gian: %d giây\nĐối thủ còn lại: %d" % [
		current_level["name"], score, int(elapsed), remaining_bots
	]


func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE + TILE * 0.5, cell.y * TILE + TILE * 0.5)


func _label(parent: Node, value: String, point: Vector2, dimensions: Vector2, font_size: int, tint: Color, centered: bool = false) -> Label:
	var label = Label.new()
	label.text = value
	label.position = point
	label.size = dimensions
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", tint)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.11, 0.21, 0.60))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _style(fill: Color, edge: Color, radius: int = 16) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = edge
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(0.0, 0.04, 0.14, 0.33)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 4)
	return sb


func _panel(parent: Node, point: Vector2, dimensions: Vector2, fill: Color, edge: Color) -> Panel:
	var panel = Panel.new()
	panel.position = point
	panel.size = dimensions
	panel.add_theme_stylebox_override("panel", _style(fill, edge))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	return panel


func _button(parent: Node, value: String, point: Vector2, dimensions: Vector2, fill: Color) -> Button:
	var b = Button.new()
	b.text = value
	b.position = point
	b.size = dimensions
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 21)
	b.add_theme_color_override("font_color", Color("073259"))
	b.add_theme_color_override("font_hover_color", Color("052441"))
	b.add_theme_color_override("font_disabled_color", Color("073259"))
	b.add_theme_stylebox_override("normal", _style(fill, fill.lightened(0.25), 14))
	b.add_theme_stylebox_override("hover", _style(fill.lightened(0.17), Color.WHITE, 14))
	b.add_theme_stylebox_override("pressed", _style(fill.darkened(0.16), fill, 14))
	b.add_theme_stylebox_override("disabled", _style(fill.darkened(0.13), Color("8ceeff"), 14))
	parent.add_child(b)
	return b
