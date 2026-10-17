extends "res://scripts/ui/pc/pc_kit.gd"
## Result and pause overlay over the arena. Rows come from the round's fighters
## (knockouts credited to the bomb owner, items picked up, hearts left). Offline
## practice grants no gold or XP, and the reward bar says so.
var game: Node
var title: Label
var subtitle: Label
var hero_art: TextureRect
var rows: VBoxContainer
var summary: Label
var actions: HBoxContainer

func _init() -> void:
	super("sunset")
	fill_screen = false

func _ready() -> void:
	name = "PcResult"
	setup()
	var root := page(canvas, 8)
	title = title_text("", 64, SUN, root)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("outline_size", 16)
	subtitle = title_text("", 20, Color.WHITE, root)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var body := row(18, root)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var hero_side := column(0, body)
	hero_side.custom_minimum_size = Vector2(300, 0)
	hero_side.alignment = BoxContainer.ALIGNMENT_CENTER
	hero_art = picture("", Vector2(300, 300))
	hero_side.add_child(hero_art)
	var shadow := card(Color(0.45, 0.22, 0.1, 0.16), Color.TRANSPARENT, 40, 0, 0)
	shadow.custom_minimum_size = Vector2(220, 20)
	shadow.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hero_side.add_child(shadow)
	var sheet := card(CREAM, Color.WHITE, 26, 5, 18)
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(sheet)
	var stack := column(10, sheet)
	stack.add_child(table_row(["#", "Người chơi", "Hạ gục", "Vật phẩm", "Tim", "Điểm"], null, MUTED, 15))
	rows = column(10, stack)
	rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var reward := PanelContainer.new()
	reward.add_theme_stylebox_override("panel", lipped(SKY, Color("2b88cf"), 6))
	stack.add_child(reward)
	summary = title_text("", 18, Color.WHITE, reward)
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	actions = row(16, stack)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	visibility_changed.connect(render)

## One table line; `face` is a portrait path or null for the header.
func table_row(values: Array, face, color := INK, font_size := 18) -> HBoxContainer:
	var line := row(10)
	var widths := [44, 0, 92, 92, 70, 92]
	for i in values.size():
		var cell: Label
		if i == 0 and face != null:
			cell = title_text(str(values[i]), font_size + 6, color, line)
		else:
			if i == 1 and face != null:
				line.add_child(picture(face, Vector2(44, 44)))
			cell = text(str(values[i]), font_size, color, line)
		if widths[i] == 0:
			stretch(cell)
		else:
			cell.custom_minimum_size = Vector2(widths[i], 0)
			cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return line

func points(actor: Dictionary) -> int:
	if not actor.bot:
		return game.score
	return int(actor.get("kills", 0)) * 100 + int(actor.get("items", 0)) * 25

func render() -> void:
	if not is_visible_in_tree() or game.player.is_empty():
		return
	var paused: bool = game.game_state == "paused"
	if paused:
		title.text = "TẠM DỪNG"
		subtitle.text = "Nhấn Esc hoặc TIẾP TỤC để chơi tiếp"
	elif game.last_won:
		title.text = "CHIẾN THẮNG!"
		subtitle.text = "Bạn đã hạ cả 3 bot"
	else:
		title.text = "THUA RỒI!"
		subtitle.text = "Hết giờ rồi" if game.remaining <= 0.0 else "Bạn đã bị loại, thử lại nhé"
	title.add_theme_color_override("font_color", SUN if paused or game.last_won else Color("9fd7ff"))
	hero_art.texture = load("res://assets/characters/portraits/%s.png" % game.player.hero)
	for child in rows.get_children():
		child.queue_free()
	var ranked: Array = game.fighters.duplicate()
	ranked.sort_custom(func(a, b): return points(a) > points(b) or (points(a) == points(b) and not a.bot and b.bot))
	for i in ranked.size():
		var actor: Dictionary = ranked[i]
		var hero_name: String = game.HERO_NAMES[game.HEROES.find(actor.hero)].capitalize()
		var who: String = (AuthSession.account_name if AuthSession.has_session() else "Bạn") + " · " + hero_name if not actor.bot else "Bot " + hero_name
		var line := card(Color("fff2df") if not actor.bot else Color.WHITE, SUN if not actor.bot else Color("cde9fb"), 16, 3, 6)
		line.add_child(table_row([i + 1, who, int(actor.get("kills", 0)), int(actor.get("items", 0)), int(actor.lives) if actor.alive else 0, points(actor)], "res://assets/characters/portraits/%s.png" % actor.hero))
		rows.add_child(line)
	summary.text = "%s · %d giây · Luyện tập offline: không cộng vàng/XP" % [str(game.current_level.get("name", "")).capitalize(), int(game.elapsed)]
	for child in actions.get_children():
		child.queue_free()
	actions.add_child(sized(candy("Về sảnh", func(): game.show_pc_screen("lobby"), "ghost", 20), Vector2(200, 58)))
	if paused:
		actions.add_child(sized(candy("Chơi lại", func(): game._new_round(), "sky", 20), Vector2(200, 58)))
		actions.add_child(sized(candy("TIẾP TỤC", func(): game._resume_game(), "sun", 24), Vector2(240, 58)))
	else:
		actions.add_child(sized(candy("CHƠI TIẾP", func(): game.show_pc_screen("room"), "sun", 24), Vector2(240, 58)))
