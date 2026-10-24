extends "res://scripts/ui/pc/pc_missions.gd"
## SĂN BOSS window (docs/BOSS.md): the boss event's schedule (Vietnam time), raid
## rules and rewards, Solo / Ghép đội / Phòng riêng, Boss quests, the Event Shop
## (Huy Hiệu Boss) and raid rewards waiting to be claimed. Everything comes from
## GET /v1/boss/events and /v1/boss/rewards; the client never decides a reward.
## Quest cards, shop cards, timers and claims reuse the mission window.
signal play(event_id: String, mode: String)

const BOSS_TABS := [["raid", "Săn Boss"], ["quests", "Nhiệm vụ Boss"], ["shop", "Đổi quà"], ["rewards", "Phần thưởng"]]
const PHASES := {"running": ["ĐANG DIỄN RA", Color("44cf9e")], "scheduled": ["SẮP MỞ", Color("4fb7f5")], "paused": ["TẠM DỪNG", Color("ffaa45")], "ended": ["ĐÃ KẾT THÚC", Color("8fa3c0")]}
const SKILLS := {
	"boss_basic_hit": "Đánh thường quanh Boss (báo trước 0,6 s)",
	"boss_aoe_mark": "Đánh dấu vùng quanh người chơi (báo trước 1,2 s)",
	"boss_block_lane": "Chặn ô bằng vật cản tạm 3 s",
	"boss_wave_push": "Sóng đẩy người và bom 2 ô",
	"boss_weak_point": "Lộ điểm yếu: ×1,5 sát thương trong 3 s",
	"robot_bomb_launch": "Bom Bật Sau Lưng: 1 bom trước mặt, nổ + 2 ô",
	"robot_bomb_chain": "Chuỗi Boom: 3 bom trước / trái / phải, nổ lần lượt",
	"robot_mini_chaser": "Bom Đuổi: bom mini đuổi theo, dừng rồi nổ + 1 ô",
	"robot_recoil_dash": "Phản Lực Boom: lướt tối đa 4 ô, để lại 1 bom",
	"robot_magnet_pull": "Hút Boom Về Lưng: nổ + 2 ô quanh thân",
	"robot_overheat": "Quá Tải Dây Cót: 8 bom quanh Boss",
	"robot_reactor": "ULTIMATE Lò Bom: 2 đợt theo hàng / cột, luôn chừa lối né",
	"cactus_thorn_roll": "Lăn Gai: lăn 4 ô theo làn báo trước; đâm tường thì choáng",
	"cactus_thorn_shot": "Gai Bay: 3 gai bay tối đa 5 ô",
	"cactus_thorn_cross": "Gai Nổ Chữ Thập: dấu + 3 ô mỗi hướng",
	"cactus_thorn_storm": "ULTIMATE Bão Gai Xoáy: 3 vòng gai, luôn có lối hở",
	"ram_thunder_charge": "Húc Sấm: húc 5 ô theo làn, đẩy lùi",
	"ram_thunder_ball": "Cầu Điện: bay tối đa 6 ô, kích nổ bom",
	"ram_lightning_cross": "Điện Nổ Chữ Thập: dấu + 3 ô mỗi hướng",
	"ram_thunder_storm": "ULTIMATE Thiên Lôi Liên Kích: 3 đợt sét, không khóa hết lối thoát",
}
const ITEM_NAMES := {"throw_bomb": "Bom ném xa", "dart": "Phi tiêu", "blue_shield": "Khiên", "speed_shoes": "Giày", "freeze_bomb": "Bom băng", "push_glove": "Găng đẩy"}

var events: Array = []
var rewards: Array = []
var selected := 0

func _ready() -> void:
	name = "PcBoss"
	current_tab = "raid"
	setup()
	var root := page(canvas)
	var head := row(10, root)
	var group := ButtonGroup.new()
	for spec in BOSS_TABS:
		var key: String = spec[0]
		var button := tab(spec[1], func(): set_tab(key), group)
		button.name = "Tab_" + key
		button.custom_minimum_size = Vector2(190, 48)
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
	when_shown(load_quests)
	render()

func event() -> Dictionary:
	return events[clampi(selected, 0, events.size() - 1)] if not events.is_empty() else {}

## Same name as the mission window, so its claim / order flows reload this page.
func load_quests() -> void:
	if busy:
		return
	if not AuthSession.has_session():
		state = "signed_out"
		events = []
		render()
		return
	if state != "ok":
		state = "loading"
		render()
	var reply: Dictionary = await AuthSession.api(HTTPClient.METHOD_GET, "/v1/boss/events")
	var pending: Dictionary = await AuthSession.api(HTTPClient.METHOD_GET, "/v1/boss/rewards")
	if reply.status == 200 and reply.data is Dictionary:
		events = reply.data.get("events", [])
		rewards = pending.data.get("rewards", []) if pending.status == 200 and pending.data is Dictionary else []
		state = "ok"
		var first: Dictionary = event()
		if not first.is_empty():
			clock_offset = parse_time(first.get("server_time", "")) - Time.get_unix_time_from_system()
		render()
	else:
		state = "error"
		error_text = str(reply.error)
		render()

## The mission-window shop and quest cards read these keys.
func as_mission_event(e: Dictionary) -> Dictionary:
	var me: Dictionary = e.get("me", {})
	return {"id": e.id, "name": e.name, "tokens": int(me.get("badges", 0)), "token_name": str(e.get("badge_name", "Huy Hiệu")), "shop": e.get("shop", []), "window": e.get("window", "closed")}

func render() -> void:
	if list == null:
		return
	clear_list()
	tokens_label.get_parent().hide()
	timer_label.get_parent().hide()
	match state:
		"signed_out":
			return message("Đăng nhập tài khoản để săn Boss. Phần thưởng chỉ ghi cho tài khoản.")
		"loading":
			return message("Đang tải sự kiện Boss…")
		"error":
			return message("Chưa tải được sự kiện Boss: %s" % error_text)
		"idle":
			return
	var e := event()
	if e.is_empty():
		header.text = ""
		return message("Hiện chưa có sự kiện Đại Chiến Boss. Hãy quay lại khi sự kiện mở!")
	var many := events.size() > 1
	if many:
		# Every boss event at once (e.g. Slime King and the robot): one card / section each.
		header.text = "%d sự kiện Boss · Giờ Việt Nam (UTC+7)" % events.size()
	else:
		var me: Dictionary = e.get("me", {})
		tokens_label.text = "%s: %d" % [str(e.get("badge_name", "Huy Hiệu")), int(me.get("badges", 0))]
		tokens_label.get_parent().show()
		match str(e.get("phase", "")):
			"scheduled":
				show_timer("Mở sau ", e.start_at)
			"running":
				show_timer("Kết thúc sau ", e.end_at)
			_:
				if e.window == "claim":
					show_timer("Nhận thưởng còn ", e.claim_end_at)
		header.text = "%s · Giờ Việt Nam (UTC+7)" % str(e.name)
	match current_tab:
		"raid":
			for one in events:
				list.add_child(raid_card(one))
		"quests":
			for one in events:
				section(one, many)
				var quests: Array = one.get("quests", [])
				if quests.is_empty():
					message("Sự kiện chưa có nhiệm vụ Boss.")
				for quest in quests:
					list.add_child(quest_card(quest, str(one.get("badge_name", "Huy Hiệu"))))
		"shop":
			for one in events:
				section(one, many)
				if one.get("shop", []).is_empty():
					message("Sự kiện chưa mở Event Shop.")
				else:
					list.add_child(shop_card(as_mission_event(one)))
		"rewards":
			if rewards.is_empty():
				message("Không có phần thưởng nào đang chờ. Thắng Boss để nhận thưởng!")
			for grant in rewards:
				list.add_child(grant_card(grant, badge_of(str(grant.get("event_id", "")))))

## Section title of one event (only when several are shown).
func section(e: Dictionary, many: bool) -> void:
	if not many:
		return
	var me: Dictionary = e.get("me", {})
	var label := title_text("%s · %s: %d" % [str(e.name), str(e.get("badge_name", "Huy Hiệu")), int(me.get("badges", 0))], 24, Color.WHITE, list)
	label.name = "Section_" + str(e.id)

func badge_of(event_id: String) -> String:
	for one in events:
		if str(one.id) == event_id:
			return str(one.get("badge_name", "Huy Hiệu"))
	return str(event().get("badge_name", "Huy Hiệu"))

func raid_card(e: Dictionary) -> PanelContainer:
	var rules: Dictionary = e.get("rules", {})
	var me: Dictionary = e.get("me", {})
	var holder := card(Color("2a1640"), Color("ff9ec0"), 22, 4, 16)
	holder.name = "BossRaid" if events.size() <= 1 else "BossRaid_" + str(e.id)
	var stack := column(10, holder)
	var head := row(14, stack)
	var titles := column(4, head)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_text(str(rules.get("display_name", "Boss Sự Kiện")), 34, Color.WHITE, titles)
	var meta := row(8, titles)
	var phase := str(e.get("phase", ""))
	var spec: Array = PHASES.get(phase, [phase, MUTED])
	pill(spec[0], spec[1], Color.WHITE, 14, meta)
	if phase == "running" and not bool(e.get("in_session", true)):
		pill("NGOÀI KHUNG GIỜ", Color("ffaa45"), Color.WHITE, 14, meta)
	pill(str(MapCatalog.find(str(rules.get("map_id", ""))).get("name", rules.get("map_id", ""))).capitalize(), SKY, Color.WHITE, 14, meta)
	var map_art := picture("", Vector2(210, 150))
	map_art.texture = MapCatalog.preview(str(rules.get("map_id", "")))
	head.add_child(map_art)
	for value in [e.get("banner", ""), e.get("intro", "")]:
		if str(value) != "":
			var label := text(str(value), 16, Color("ffe1ec"), stack)
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var sessions: Array = rules.get("sessions", [])
	var hours := "Cả ngày trong thời gian sự kiện"
	if not sessions.is_empty():
		var spans: Array[String] = []
		for s in sessions:
			spans.append("%s-%s" % [s.local_start, s.local_end])
		hours = "Khung giờ " + ", ".join(spans)
	var facts := [
		"Đội %d-%d người · %d phút · %s" % [int(rules.get("min_players", 1)), int(rules.get("max_players", 8)), int(rules.get("duration_seconds", 300)) / 60, hours],
		"HP Boss: %d (1 người) đến %d (8 người) · %d giai đoạn" % [int(rules.get("hp_solo", 0)), int(rules.get("hp_full", 0)), rules.get("phase_thresholds", []).size() + 1],
		"Thắng: %s · Thua/hết giờ: %s" % [reward_text(rules.get("win_rewards", []), str(e.get("badge_name", ""))), reward_text(rules.get("lose_rewards", []), str(e.get("badge_name", "")))],
		"Lượt thưởng đầy đủ hôm nay: %d/%d · Đã thắng %d trận · Chờ nhận %d" % [int(me.get("full_rewards_today", 0)), int(rules.get("full_reward_limit_per_day", 3)), int(me.get("wins", 0)), int(me.get("pending_rewards", 0))],
	]
	if int(rules.get("rescue_ms", 0)) > 0:
		facts.append("Trúng đòn Boss bị nhốt bóng nước %.0f giây: đồng đội chạm vào để cứu" % (float(rules.rescue_ms) / 1000.0))
	if events.size() > 1:
		# The page header shows one event's badges and timer; with several, each card does.
		var until := parse_time(e.end_at if phase != "scheduled" else e.start_at)
		var when := ("Mở sau " if phase == "scheduled" else "Kết thúc sau ") + countdown(until - server_now()) if until > 0.0 else ""
		facts.append("%s: %d%s" % [str(e.get("badge_name", "Huy Hiệu")), int(me.get("badges", 0)), " · " + when if when != "" else ""])
	for fact in facts:
		var label := text("• " + fact, 16, Color.WHITE, stack)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var skills: Array[String] = []
	for skill in rules.get("skills", []):
		skills.append(SKILLS.get(str(skill), str(skill)))
	var skill_label := text("Kỹ năng Boss: " + "; ".join(skills) + ". Ô cảnh báo hiện trước khi trúng đòn.", 14, Color("ffd84d"), stack)
	skill_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var items: Array[String] = []
	for item in rules.get("items", []):
		items.append(ITEM_NAMES.get(str(item), str(item)))
	text("Vật phẩm dùng được: %s%s" % [", ".join(items) if not items.is_empty() else "không", " · thú cưỡi" if bool(rules.get("mount", true)) else ""], 14, Color("bfe3fb"), stack)
	var actions := row(12, stack)
	var open := bool(e.get("open", false))
	var event_id := str(e.id)
	for spec_button in [["SOLO", "solo", "sun"], ["GHÉP ĐỘI", "team", "mint"], ["PHÒNG RIÊNG", "private", "ghost"]]:
		var mode: String = spec_button[1]
		var button := candy(spec_button[0], func(): request_play(event_id, mode, bool(rules.get("reward_private_room", false))), spec_button[2], 22)
		button.name = "Play_" + mode
		button.custom_minimum_size = Vector2(220, 64)
		button.disabled = not open
		actions.add_child(button)
	if not open:
		var why := "Sự kiện chưa mở hoặc đang tạm dừng."
		if phase == "running" and not bool(e.get("in_session", true)):
			var next := parse_time(e.get("next_session", ""))
			why = "Ngoài khung giờ chơi." + (" Mở lại sau %s." % countdown(next - server_now()) if next > 0.0 else "")
		text(why, 15, Color("ffaa45"), stack)
	return holder

func request_play(event_id: String, mode: String, private_rewards: bool) -> void:
	if mode == "private" and not private_rewards:
		notice("PHÒNG RIÊNG", "Phòng riêng để chơi cùng bạn bè, không nhận thưởng kinh tế (xu, Huy Hiệu). Vẫn tạo phòng?", func(): play.emit(event_id, mode), "TẠO PHÒNG")
		return
	play.emit(event_id, mode)

func grant_card(grant: Dictionary, badge: String) -> PanelContainer:
	var holder := card(Color("fff6dc"), SUN, 18, 3, 12)
	holder.name = "Grant_" + str(grant.id).left(8)
	var line := row(14, holder)
	var body := column(4, line)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stretch(text("Thưởng trận Boss" + (" (an ủi)" if str(grant.kind) == "consolation" else ""), 20, INK, body))
	text(reward_text(grant.get("rewards", []), badge), 16, Color("d9890b"), body)
	var button := candy("NHẬN", func(): claim_grant(str(grant.id)), "sun", 18)
	button.name = "Claim"
	button.custom_minimum_size = Vector2(150, 56)
	button.disabled = busy
	line.add_child(button)
	return holder

func claim_grant(grant_id: String) -> void:
	if busy:
		return
	busy = true
	render()
	var reply: Dictionary = await AuthSession.api(HTTPClient.METHOD_POST, "/v1/boss/rewards/%s/claim" % grant_id.uri_encode(), {"request_id": UIState.request_id()})
	busy = false
	if reply.status == 200 and reply.data is Dictionary:
		if reply.data.get("wallet") is Dictionary:
			UIState.apply_wallet(reply.data.wallet)
		UIState.toast_requested.emit("Đã nhận thưởng Boss")
	else:
		notice("NHẬN THƯỞNG", "Chưa nhận được thưởng: %s" % str(reply.error))
	await load_quests()
