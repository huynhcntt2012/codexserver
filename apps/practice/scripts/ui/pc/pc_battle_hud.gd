extends "res://scripts/ui/pc/pc_kit.gd"
## Full-screen battle HUD. The window keeps any aspect (no black bars): the arena
## is scaled to fill the space left of a sidebar (map, time limit, players, exit)
## and above a stats bar. Read-only view of `game` except pausing and the arena
## placement it hands to `game.layout_arena`.
const BANNER_TIME := 1.3
const SIDEBAR := 260.0
const BAR := 66.0
const GAP := 12.0

var game: Node
var map_label: Label
var bots_label: Label
var timer_label: Label
var status_label: Label
var banner: Label
var players: Array[Dictionary] = []
var stats: Dictionary = {}
var sidebar: PanelContainer
var bar: PanelContainer
var frame: Panel
var arena_rect := Rect2()
var laid_out_for := Rect2()

func _init() -> void:
	super("sky")
	fill_screen = false

func _ready() -> void:
	name = "PcBattleHud"
	setup()
	sky.hide()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Thin frame around the arena; transparent inside so the board stays visible.
	frame = Panel.new()
	var rim := box(Color.TRANSPARENT, Color("0d2f5c"), 18, 8, 0)
	rim.draw_center = false
	rim.shadow_color = Color(0.02, 0.12, 0.3, 0.35)
	rim.shadow_size = 10
	frame.add_theme_stylebox_override("panel", rim)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(frame)
	build_sidebar()
	build_bar()
	banner = title_text("BẮT ĐẦU!", 96, Color.WHITE, canvas)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.add_theme_constant_override("outline_size", 22)

func build_sidebar() -> void:
	sidebar = card(Color("1567ae", 0.96), Color("74d3f0"), 22, 4, 12)
	sidebar.mouse_filter = Control.MOUSE_FILTER_PASS
	canvas.add_child(sidebar)
	var stack := column(10, sidebar)
	var head := row(6, stack)
	map_label = stretch(title_text("", 20, Color.WHITE, head))
	var pause := round_icon("gear", func(): game._pause_game(), "ghost", 40)
	pause.tooltip_text = "Tạm dừng (Esc)"
	pause.focus_mode = Control.FOCUS_NONE
	head.add_child(pause)
	text("● Luyện tập offline", 13, Color("7ff0c2"), stack)
	var clock := PanelContainer.new()
	clock.add_theme_stylebox_override("panel", lipped(Color("0d3f78"), Color("08284f"), 5))
	stack.add_child(clock)
	var clock_line := row(8, clock)
	text("GIỚI HẠN", 15, Color("9fd7ff"), clock_line)
	timer_label = title_text("", 34, Color.WHITE, clock_line)
	timer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var bots_line := row(6, stack)
	text("Bot còn lại", 15, Color("d5f3ff"), bots_line)
	spacer(bots_line)
	bots_label = title_text("", 26, CORAL, bots_line)
	bots_label.tooltip_text = "Bot còn lại"
	text("NGƯỜI CHƠI", 14, Color("9fd7ff"), stack)
	for i in 4:
		var entry := card(Color("e9f6ff"), Color("9fd7ff"), 14, 3, 6)
		stack.add_child(entry)
		var line := row(8, entry)
		var face_frame := card(Color("ffe9b0"), Color.WHITE, 24, 2, 0)
		face_frame.custom_minimum_size = Vector2(48, 48)
		line.add_child(face_frame)
		var face := picture("", Vector2(46, 46))
		face_frame.add_child(face)
		var words := column(-2, line)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var who := stretch(text("", 15, INK, words))
		var state := text("", 12, MINT, words)
		var kills := title_text("", 18, SUN, line)
		kills.tooltip_text = "Hạ gục"
		players.append({"line": entry, "face": face, "name": who, "state": state, "kills": kills})
	spacer(stack, true)
	var keys := text("WASD / mũi tên: di chuyển · Space: đặt bom\nEsc: tạm dừng · R: chơi lại · M: âm thanh", 11, Color("d5f3ff"), stack)
	keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var leave := candy("THOÁT RA", func(): game._pause_game(), "coral", 22)
	leave.name = "Leave"
	leave.tooltip_text = "Tạm dừng để về sảnh, chơi lại hoặc tiếp tục"
	leave.focus_mode = Control.FOCUS_NONE
	leave.custom_minimum_size = Vector2(0, 56)
	stack.add_child(leave)

func build_bar() -> void:
	bar = card(Color("1567ae", 0.96), Color("74d3f0"), 20, 4, 8)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(bar)
	var line := row(10, bar)
	title_text("CHỈ SỐ", 18, Color.WHITE, line)
	for spec in [["lives", "res://assets/items/heart.png"], ["bombs", "res://assets/items/extra_bomb.png"], ["range", "res://assets/items/flame.png"], ["speed", "res://assets/items/shoe.png"]]:
		var chip := card(Color("e9f6ff"), Color("9fd7ff"), 14, 2, 4)
		line.add_child(chip)
		var chip_line := row(4, chip)
		chip_line.add_child(picture(spec[1], Vector2(30, 30)))
		stats[spec[0]] = text("", 15, INK, chip_line)
	var score := card(Color("fff4d4"), SUN, 14, 2, 4)
	line.add_child(score)
	var score_line := row(6, score)
	text("Điểm", 14, INK, score_line)
	stats["score"] = title_text("", 22, SUN, score_line)
	status_label = stretch(text("", 15, Color.WHITE, line))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

## Board size of the loaded map in pixels (15x11 or 17x13 tiles of 64 px).
func arena_size() -> Vector2:
	return Vector2(game.columns * game.TILE, game.rows * game.TILE)

## Places sidebar, bar and arena for the current window; the arena keeps the
## map's proportions and grows to the largest size that fits.
func layout() -> void:
	var area := canvas.size
	var key := Rect2(area, arena_size())
	if key == laid_out_for or area.x <= 0.0:
		return
	laid_out_for = key
	var side_x := area.x - SIDEBAR - GAP
	sidebar.position = Vector2(side_x, GAP)
	sidebar.size = Vector2(SIDEBAR, area.y - GAP * 2)
	var left := Rect2(GAP, GAP, side_x - GAP * 2, area.y - BAR - GAP * 3)
	bar.position = Vector2(GAP, area.y - BAR - GAP)
	bar.size = Vector2(left.size.x, BAR)
	var board := arena_size()
	var fit := minf(left.size.x / board.x, left.size.y / board.y)
	var size := board * fit
	arena_rect = Rect2(left.position + (left.size - size) / 2.0, size)
	frame.position = arena_rect.position - Vector2(8, 8)
	frame.size = arena_rect.size + Vector2(16, 16)
	banner.position = arena_rect.position
	banner.size = arena_rect.size
	# Canvas units -> viewport units for the 2D world under the HUD.
	game.layout_arena(Rect2(arena_rect.position * canvas.scale, arena_rect.size * canvas.scale), get_viewport_rect().size)

func refresh() -> void:
	if game.player.is_empty():
		return
	map_label.text = str(game.current_level.get("name", "")).capitalize()
	bots_label.text = str(game.remaining_bots)
	var seconds := int(ceil(game.remaining))
	timer_label.text = "%d:%02d" % [seconds / 60, seconds % 60]
	timer_label.add_theme_color_override("font_color", Color("ffe17b") if seconds <= 30 else Color.WHITE)
	for i in players.size():
		var entry: Dictionary = players[i]
		(entry.line as Control).visible = i < game.fighters.size()
		if i >= game.fighters.size():
			continue
		var actor: Dictionary = game.fighters[i]
		var hero_index: int = game.HEROES.find(actor.hero)
		(entry.face as TextureRect).texture = load("res://assets/characters/portraits/%s.png" % actor.hero)
		(entry.face as TextureRect).modulate.a = 1.0 if actor.alive else 0.45
		(entry.name as Label).text = ("Bot " if actor.bot else "") + game.HERO_NAMES[hero_index].capitalize()
		(entry.name as Label).add_theme_color_override("font_color", game.HERO_COLORS[hero_index].darkened(0.25))
		(entry.state as Label).text = ("Đang chơi" if actor.bot else "Tim %d/3" % int(actor.lives)) if actor.alive else "Bị loại"
		(entry.state as Label).add_theme_color_override("font_color", MINT.darkened(0.15) if actor.alive else CORAL)
		(entry.kills as Label).text = "×%d" % int(actor.get("kills", 0))
	stats["lives"].text = "Tim %d/3" % int(game.player.lives)
	stats["bombs"].text = "Bom ×%d" % int(game.player.bomb_capacity)
	stats["range"].text = "Tầm %d" % int(game.player.bomb_range)
	stats["speed"].text = "Tốc độ %.1f" % float(game.player.speed)
	stats["score"].text = grouped(game.score)
	status_label.text = game.status_message if game.status_timeout > 0.0 else "Phá thùng, nhặt vật phẩm và hạ 3 bot!"
	banner.visible = game.game_state == "playing" and game.elapsed < BANNER_TIME
	banner.modulate.a = clampf((BANNER_TIME - game.elapsed) / 0.4, 0.0, 1.0)

func _process(delta: float) -> void:
	super._process(delta)
	if not is_visible_in_tree():
		return
	# Battle fills the monitor like the menus; no letterbox bars.
	ScreenFill.set_fill(get_tree(), true)
	layout()
	refresh()
