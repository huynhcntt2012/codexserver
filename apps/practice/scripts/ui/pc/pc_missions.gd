extends "res://scripts/ui/pc/pc_kit.gd"
## PC mission window (docs/LIVEOPS.md): four tabs — Hằng ngày, Hằng tuần, Cốt truyện,
## Sự kiện (banner, event quests, Event Shop). Everything comes from GET /v1/quests;
## the client never counts progress. Claims and shop orders carry a request id so a
## retry never pays twice; buttons lock while a request is in flight.
signal navigate(destination: String)
signal claimable_changed(count: int)

const TABS := [["daily", "Hằng ngày"], ["weekly", "Hằng tuần"], ["story", "Cốt truyện"], ["event", "Sự kiện"]]
const RULE_ICONS := {
	"MATCH_COMPLETED": "res://assets/items/clock.png",
	"MATCH_WON": "res://assets/items/flame.png",
	"BOMB_PLACED": "res://assets/items/extra_bomb.png",
	"MAPS_DISTINCT": "res://assets/items/range.png",
	"LOGIN_DAY": "res://assets/items/heart.png",
	"WITH_FRIEND": "res://assets/items/wing.png",
}
const STATUS := {
	"in_progress": ["Đang làm", Color("8fa3c0")],
	"completed": ["NHẬN", Color("44cf9e")],
	"claimed": ["ĐÃ NHẬN", Color("b3c1d6")],
	"expired": ["Hết hạn", Color("b3c1d6")],
	"locked": ["Chưa mở", Color("b3c1d6")],
}
const REFRESH_SECONDS := 60.0

var current_tab := "daily"
var data: Dictionary = {}
var state := "idle"  # idle | loading | ok | error | signed_out
var error_text := ""
var busy := false
var clock_offset := 0.0  # server_now - local unix time, seconds
var refresh_clock := 0.0
var tab_buttons: Dictionary = {}
var header: Label
var timer_label: Label
var tokens_label: Label
var list: VBoxContainer
var scroll: ScrollContainer

func _init() -> void:
	super("sky")

func _ready() -> void:
	name = "PcMissions"
	setup()
	var root := page(canvas)
	var head := row(10, root)
	var group := ButtonGroup.new()
	for spec in TABS:
		var key: String = spec[0]
		var button := tab(spec[1], func(): set_tab(key), group)
		button.name = "Tab_" + key
		button.custom_minimum_size = Vector2(170, 48)
		button.add_theme_font_size_override("font_size", 18)
		button.button_pressed = key == current_tab
		head.add_child(button)
		tab_buttons[key] = button
	spacer(head)
	tokens_label = pill("", Color("a98bf0"), Color.WHITE, 16, head)
	timer_label = pill("", NAVY, Color.WHITE, 16, head)
	header = text("", 16, MUTED, root)
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	list = column(10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	build_modal()
	visibility_changed.connect(func(): if is_visible_in_tree(): load_quests())
	render()

func set_tab(key: String) -> void:
	current_tab = key
	for k in tab_buttons:
		(tab_buttons[k] as Button).set_pressed_no_signal(k == key)
	render()

func server_now() -> float:
	return Time.get_unix_time_from_system() + clock_offset

static func parse_time(value: Variant) -> float:
	var text_value := str(value)
	if text_value.is_empty() or text_value == "<null>":
		return 0.0
	# "2026-10-17T00:00:00+00:00" / "...Z": Godot reads the UTC wall clock.
	return Time.get_unix_time_from_datetime_string(text_value.left(19)) - _zone_seconds(text_value)

static func _zone_seconds(value: String) -> float:
	var tail := value.substr(19)
	var zone := tail.right(6)
	if zone.length() == 6 and (zone[0] == "+" or zone[0] == "-") and zone[3] == ":":
		var seconds := int(zone.substr(1, 2)) * 3600 + int(zone.substr(4, 2)) * 60
		return seconds if zone[0] == "+" else -seconds
	return 0.0

static func countdown(seconds: float) -> String:
	var left := maxi(0, int(seconds))
	if left >= 86400:
		return "%d ngày %d giờ" % [left / 86400, (left % 86400) / 3600]
	if left >= 3600:
		return "%d giờ %02d phút" % [left / 3600, (left % 3600) / 60]
	return "%d phút %02d giây" % [left / 60, left % 60]

func load_quests() -> void:
	if busy:
		return
	if not AuthSession.has_session():
		state = "signed_out"
		data = {}
		render()
		return
	if state != "ok":
		state = "loading"
		render()
	var reply: Dictionary = await AuthSession.api(HTTPClient.METHOD_GET, "/v1/quests")
	if reply.status == 200 and reply.data is Dictionary:
		apply(reply.data)
	else:
		state = "error"
		error_text = str(reply.error)
		render()

func apply(payload: Dictionary) -> void:
	data = payload
	state = "ok"
	clock_offset = parse_time(payload.get("server_now", "")) - Time.get_unix_time_from_system()
	claimable_changed.emit(int(payload.get("claimable", 0)))
	render()

func story_event() -> Dictionary:
	for event in data.get("events", []):
		if not event.get("chapters", []).is_empty():
			return event
	return {}

func shop_event() -> Dictionary:
	for event in data.get("events", []):
		if not event.get("quests", []).is_empty() or not event.get("shop", []).is_empty():
			return event
	return story_event()

func clear_list() -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()

func render() -> void:
	if list == null:
		return
	clear_list()
	tokens_label.get_parent().hide()
	timer_label.get_parent().hide()
	match state:
		"signed_out":
			return message("Đăng nhập tài khoản để làm nhiệm vụ và nhận thưởng. Chế độ khách không lưu tiến độ.")
		"loading":
			return message("Đang tải nhiệm vụ…")
		"error":
			return message("Chưa tải được nhiệm vụ: %s" % error_text)
		"idle":
			return
	match current_tab:
		"daily", "weekly":
			var section: Dictionary = data.get(current_tab, {})
			header.text = "Nhiệm vụ %s đặt lại lúc 00:00 (giờ Việt Nam)%s. Tiến độ tính từ trận do máy chủ ghi nhận." % ["hằng ngày" if current_tab == "daily" else "hằng tuần", "" if current_tab == "daily" else " thứ Hai"]
			show_timer("Đặt lại sau ", section.get("resets_at", ""))
			var quests: Array = section.get("quests", [])
			if quests.is_empty():
				message("Chưa có nhiệm vụ. Admin bật nhiệm vụ trong trang quản trị.")
			for quest in quests:
				list.add_child(quest_card(quest, "Vé"))
		"story":
			var event := story_event()
			if event.is_empty():
				header.text = ""
				return message("Hiện chưa có sự kiện cốt truyện. Hãy quay lại khi sự kiện mới mở!")
			event_header(event)
			for chapter in event.get("chapters", []):
				list.add_child(chapter_card(event, chapter))
		"event":
			var event := shop_event()
			if event.is_empty():
				header.text = ""
				return message("Hiện chưa có sự kiện nào đang diễn ra.")
			event_header(event)
			list.add_child(banner_card(event))
			for quest in event.get("quests", []):
				list.add_child(quest_card(quest, str(event.token_name)))
			if not event.get("shop", []).is_empty():
				list.add_child(shop_card(event))

func message(value: String) -> void:
	var holder := card(Color(GLASS, 0.95), Color.WHITE, 20, 3, 24)
	list.add_child(holder)
	var label := text(value, 18, MUTED, holder)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func show_timer(prefix: String, at: Variant) -> void:
	var end := parse_time(at)
	if end <= 0.0:
		return
	timer_label.text = prefix + countdown(end - server_now())
	timer_label.set_meta("end", end)
	timer_label.set_meta("prefix", prefix)
	timer_label.get_parent().show()

func event_header(event: Dictionary) -> void:
	header.text = "%s · %s" % [event.name, event.get("description", "")]
	tokens_label.text = "%s: %d" % [event.token_name, int(event.get("tokens", 0))]
	tokens_label.get_parent().show()
	if event.window == "claim":
		show_timer("Sự kiện đã kết thúc · nhận thưởng còn ", event.claim_end_at)
	else:
		show_timer("Kết thúc sau ", event.end_at)

func reward_text(rewards: Array, token_name: String) -> String:
	var parts: Array[String] = []
	for reward in rewards:
		match str(reward.type):
			"gold": parts.append("%s xu" % grouped(int(reward.amount)))
			"gem": parts.append("%s KC" % grouped(int(reward.amount)))
			"token": parts.append("%d %s" % [int(reward.amount), token_name])
			"item":
				var item := UIState.get_item(str(reward.item_id))
				parts.append("%s ×%d" % [str(item.get("name", reward.item_id)), int(reward.amount)])
	return " + ".join(parts)

## One quest: rule icon, title, each objective as a progress bar, rewards, button.
func quest_card(quest: Dictionary, token_name: String) -> PanelContainer:
	var status := str(quest.get("status", "in_progress"))
	var holder := card(Color("fff6dc") if status == "completed" else Color(GLASS, 0.96), SUN if status == "completed" else Color.WHITE, 18, 3, 12)
	holder.name = "Quest_" + str(quest.key).replace(".", "_")
	var line := row(14, holder)
	var objectives: Array = quest.get("objectives", [])
	var first: Dictionary = objectives[0] if not objectives.is_empty() else {}
	line.add_child(picture(RULE_ICONS.get(str(first.get("type", "")), "res://assets/items/mystery.png"), Vector2(56, 56)))
	var body := column(4, line)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stretch(text(str(quest.title), 20, INK, body))
	if str(quest.get("description", "")) != "":
		stretch(text(str(quest.description), 14, MUTED, body))
	for objective in objectives:
		var bar_line := row(8, body)
		var label := str(objective.get("label", objective.type))
		if not objective.get("map_ids", []).is_empty():
			var names: Array[String] = []
			for map_id in objective.map_ids:
				names.append(str(MapCatalog.find(str(map_id)).get("name", map_id)).capitalize())
			label += " · " + ", ".join(names)
		if "practice" in objective.get("modes", []):
			label += " · tính cả Luyện tập"
		var caption := stretch(text(label, 14, INK, bar_line))
		caption.custom_minimum_size = Vector2(260, 0)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = maxf(1.0, float(objective.target))
		bar.value = float(objective.progress)
		bar.custom_minimum_size = Vector2(220, 14)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.add_theme_stylebox_override("background", box(Color("dfe8f3"), Color.TRANSPARENT, 7))
		bar.add_theme_stylebox_override("fill", box(MINT if bar.value >= bar.max_value else SKY, Color.TRANSPARENT, 7))
		bar_line.add_child(bar)
		text("%d/%d" % [int(objective.progress), int(objective.target)], 15, INK, bar_line)
	var prize := text("Thưởng: " + reward_text(quest.get("rewards", []), token_name), 15, Color("d9890b"), body)
	prize.name = "Rewards"
	var spec: Array = STATUS.get(status, STATUS.in_progress)
	var button := candy(spec[0], func(): claim(str(quest.key)), "sun" if status == "completed" else "ghost", 18)
	button.name = "Claim"
	button.custom_minimum_size = Vector2(150, 56)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.disabled = status != "completed" or busy
	line.add_child(button)
	return holder

func chapter_card(event: Dictionary, chapter: Dictionary) -> PanelContainer:
	var chapter_state := str(chapter.get("state", "locked"))
	var holder := card(Color.WHITE if chapter_state != "locked" else Color("eef2f7"), MINT if chapter_state == "cleared" else Color("bfe3fb"), 20, 3, 12)
	holder.name = "Chapter_" + str(chapter.key)
	var stack := column(8, holder)
	var head := row(12, stack)
	if str(chapter.get("map_id", "")) != "":
		var art := picture("", Vector2(120, 80))
		art.texture = MapCatalog.preview(str(chapter.map_id))
		head.add_child(art)
	var words := column(4, head)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stretch(title_text(str(chapter.title), 22, INK, words))
	var labels := {"locked": "Chưa mở", "playable": "Đang mở", "cleared": "Hoàn thành"}
	var colors := {"locked": Color("8fa3c0"), "playable": SKY, "cleared": MINT}
	var meta := row(8, words)
	pill(labels.get(chapter_state, chapter_state), colors.get(chapter_state, SKY), Color.WHITE, 13, meta)
	if chapter_state == "locked":
		var unlock := parse_time(chapter.get("unlock_at", ""))
		text("Mở sau %s" % countdown(unlock - server_now()) if unlock > server_now() else "Cần hoàn thành chương trước", 14, MUTED, meta)
	if str(chapter.get("npc_line", "")) != "":
		var line := text("%s: “%s”" % [str(chapter.get("npc", event.get("npc", ""))), chapter.npc_line], 15, Color("7c62c9"), words)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for quest in chapter.get("quests", []):
		stack.add_child(quest_card(quest, str(event.token_name)))
	return holder

func banner_card(event: Dictionary) -> PanelContainer:
	var holder := card(Color("ffb9d0"), Color.WHITE, 22, 4, 0)
	holder.name = "EventBanner"
	holder.custom_minimum_size = Vector2(0, 120)
	holder.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	holder.add_child(Backdrop.new("candy"))
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	holder.add_child(margin)
	var line := row(16, margin)
	line.add_child(picture("res://assets/characters/portraits/mimi.png", Vector2(96, 96)))
	var words := column(4, line)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := title_text(str(event.name), 30, Color.WHITE, words)
	title.add_theme_color_override("font_outline_color", Color("d74d63"))
	title.add_theme_constant_override("outline_size", 10)
	for value in [event.get("banner", ""), event.get("intro", "")]:
		if str(value) != "":
			var label := text(str(value), 15, INK, words)
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return holder

func shop_card(event: Dictionary) -> PanelContainer:
	var holder := card(Color("1567ae"), Color("74d3f0"), 20, 4, 12)
	holder.name = "EventShop"
	var stack := column(10, holder)
	var head := row(10, stack)
	title_text("ĐỔI QUÀ SỰ KIỆN", 22, Color.WHITE, head)
	spacer(head)
	pill("Bạn có %d %s" % [int(event.tokens), event.token_name], SUN, Color("6b3d10"), 15, head)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	stack.add_child(grid)
	var open: bool = event.window == "progress" or event.window == "claim"
	for entry in event.get("shop", []):
		var tile := card(Color("eef8ff"), Color("b8e9f7"), 16, 3, 8)
		tile.name = "Sku_" + str(entry.sku)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(tile)
		var col := column(4, tile)
		var item := UIState.get_item(str(entry.item_id))
		var art := picture("", Vector2(72, 72))
		art.texture = icon_texture(str(item.get("icon", "")))
		col.add_child(art)
		var name_label := text(str(entry.get("name", item.get("name", entry.item_id))), 15, INK, col)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.clip_text = true
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var limits := "Đã đổi %d/%d" % [int(entry.bought), int(entry.per_player)]
		if entry.get("left") != null:
			limits += " · còn %d" % int(entry.left)
		var limit_label := text(limits, 12, MUTED, col)
		limit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var reason := ""
		if bool(entry.get("owned", false)):
			reason = "ĐÃ CÓ"
		elif int(entry.bought) >= int(entry.per_player):
			reason = "ĐÃ ĐỔI"
		elif entry.get("left") != null and int(entry.left) <= 0:
			reason = "HẾT HÀNG"
		elif int(event.tokens) < int(entry.cost):
			reason = "THIẾU VÉ"
		var sku := str(entry.sku)
		var event_id := str(event.id)
		var buy := candy(reason if reason != "" else "ĐỔI %d" % int(entry.cost), func(): order(event_id, sku), "mint", 15)
		buy.name = "Buy"
		buy.disabled = reason != "" or busy or not open
		buy.tooltip_text = "%d %s" % [int(entry.cost), event.token_name]
		col.add_child(buy)
	return holder

func claim(quest_key: String) -> void:
	if busy:
		return
	busy = true
	render()
	var reply: Dictionary = await AuthSession.api(HTTPClient.METHOD_POST, "/v1/quests/%s/claim" % quest_key.uri_encode(), {"request_id": UIState.request_id()})
	busy = false
	if reply.status == 200 and reply.data is Dictionary:
		if reply.data.get("wallet") is Dictionary:
			UIState.apply_wallet(reply.data.wallet)
		UIState.toast_requested.emit("Đã nhận: " + reward_text(reply.data.get("rewards", []), "Vé"))
	else:
		notice("NHẬN THƯỞNG", "Chưa nhận được thưởng: %s" % str(reply.error))
	await load_quests()

func order(event_id: String, sku: String) -> void:
	if busy:
		return
	busy = true
	render()
	var reply: Dictionary = await AuthSession.api(HTTPClient.METHOD_POST, "/v1/events/%s/shop/orders" % event_id.uri_encode(), {"sku": sku, "request_id": UIState.request_id()})
	busy = false
	if reply.status == 201:
		UIState.toast_requested.emit("Đổi quà thành công")
		UIState.sync_wallet()
	else:
		notice("ĐỔI QUÀ", "Chưa đổi được: %s" % str(reply.error))
	await load_quests()

func _process(delta: float) -> void:
	super(delta)
	if not is_visible_in_tree():
		return
	if timer_label and timer_label.get_parent().visible and timer_label.has_meta("end"):
		timer_label.text = str(timer_label.get_meta("prefix")) + countdown(float(timer_label.get_meta("end")) - server_now())
	refresh_clock -= delta
	if refresh_clock <= 0.0:
		refresh_clock = REFRESH_SECONDS
		if state == "ok" and not busy:
			load_quests()

func _unhandled_key_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		if modal.visible:
			get_viewport().set_input_as_handled()
			close_modal()
		elif not embedded:
			get_viewport().set_input_as_handled()
			navigate.emit("home")
