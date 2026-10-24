extends Control
## Voice panel for the PC battle screens (docs/VOICE.md): a "Voice" pill next to
## the chat pill opens the channel card: who is in it (speaking, muted by you),
## your mic level, mic / speaker toggles, the push-to-talk hint and a link to
## the voice settings. The owner calls set_members() from its player list;
## state comes from VoiceChat. Offline (practice with local bots) it only says
## that voice works in online matches.

const WIDTH := 400.0

var kit: Control
var on_settings: Callable
var online := false
var members: Array = []  # [{id, name, hero, me}]
var pill: Button
var panel: PanelContainer
var title: Label
var status: Label
var rows: VBoxContainer
var meter: ProgressBar
var hint: Label
var mic_button: Button
var speaker_button: Button
var built_for := ""

func _init(owner_kit: Control, settings: Callable) -> void:
	kit = owner_kit
	on_settings = settings
	name = "VoicePanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	pill = kit.candy("Voice", func(): set_open(true), "mint", 18, "")
	pill.name = "VoicePill"
	pill.focus_mode = Control.FOCUS_NONE
	pill.size = Vector2(110, 44)
	add_child(pill)
	panel = kit.card(Color("1567ae", 0.94), Color("74d3f0"), 20, 4, 10)
	panel.name = "VoiceCard"
	panel.size = Vector2(WIDTH, 0)
	add_child(panel)
	var stack: VBoxContainer = kit.column(8, panel)
	var head: HBoxContainer = kit.row(8, stack)
	title = kit.stretch(kit.title_text("Voice", 24, Color.WHITE, head))
	var gear: Button = kit.round_icon("gear", func(): on_settings.call(), "ghost", 36)
	gear.name = "VoiceSettings"
	gear.tooltip_text = "Cài đặt giọng nói"
	gear.focus_mode = Control.FOCUS_NONE
	head.add_child(gear)
	var hide_button: Button = kit.round_icon("down", func(): set_open(false), "ghost", 36)
	hide_button.name = "Minimize"
	hide_button.focus_mode = Control.FOCUS_NONE
	head.add_child(hide_button)
	status = kit.text("", 14, Color("7ff0c2"), stack)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(WIDTH - 30, 0)
	rows = kit.column(6, stack)
	var mine: HBoxContainer = kit.row(8, stack)
	kit.text("Mic của bạn", 14, Color("d6e8ff"), mine)
	meter = ProgressBar.new()
	meter.name = "MicLevel"
	meter.show_percentage = false
	meter.max_value = 1.0
	meter.custom_minimum_size = Vector2(0, 12)
	meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meter.add_theme_stylebox_override("background", kit.box(Color("0d3f78"), Color.TRANSPARENT, 6))
	meter.add_theme_stylebox_override("fill", kit.box(kit.MINT, Color.TRANSPARENT, 6))
	mine.add_child(meter)
	var buttons: HBoxContainer = kit.row(8, stack)
	mic_button = kit.candy("Tắt mic", func(): VoiceChat.toggle_mic(); refresh(), "mint", 16)
	mic_button.name = "MicToggle"
	mic_button.focus_mode = Control.FOCUS_NONE
	mic_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(mic_button)
	speaker_button = kit.candy("Tắt loa", func(): VoiceChat.toggle_deafen(); refresh(), "sky", 16)
	speaker_button.name = "SpeakerToggle"
	speaker_button.focus_mode = Control.FOCUS_NONE
	speaker_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(speaker_button)
	hint = kit.text("", 14, kit.SUN, stack)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(WIDTH - 30, 0)
	set_open(false)

## Bottom-left anchor: the pill sits at `at`, the card opens above it.
func place(at: Vector2) -> void:
	position = at
	pill.position = Vector2(0, -pill.size.y)

func set_open(value: bool) -> void:
	panel.visible = value
	pill.visible = not value
	if value:
		built_for = ""
		refresh()

func set_members(list: Array) -> void:
	members = list
	if panel.visible:
		refresh()

func refresh() -> void:
	if panel == null or not panel.visible:
		return
	var enabled := bool(VoiceChat.setting("enabled"))
	var team := str(VoiceChat.setting("channel")) == "team"
	title.text = "Voice đội" if team else "Voice phòng"
	if not online:
		status.text = "Voice chỉ dùng trong trận online với người thật."
	elif not enabled:
		status.text = "Voice đang tắt trong Cài đặt › Âm thanh."
	elif team and str(OnlineArena.snapshot.get("mode", "")) != "boss":
		status.text = "Đấu tự do không có đồng đội: chọn Kênh toàn bộ trong cài đặt để mọi người nghe bạn."
	else:
		status.text = "● Đã kết nối kênh thoại" if OnlineArena.connected else "Mất kết nối máy chủ"
	var key := str(VoiceChat.setting("key"))
	hint.text = ("Giữ %s để nói" % key) if str(VoiceChat.setting("mode")) == "ptt" else "Mic mở: tự gửi khi bạn nói"
	mic_button.text = "Bật mic" if VoiceChat.mic_muted else "Tắt mic"
	speaker_button.text = "Bật loa" if VoiceChat.deafened else "Tắt loa"
	mic_button.disabled = not online or not enabled
	speaker_button.disabled = not online or not enabled
	var signature := JSON.stringify(members) + str(VoiceChat.blocked.keys())
	if signature == built_for:
		return
	built_for = signature
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	for m in members:
		rows.add_child(member_row(m))

func member_row(m: Dictionary) -> Control:
	var holder: PanelContainer = kit.card(Color("e9f6ff"), Color("9fd7ff"), 14, 2, 6)
	holder.name = "Member_" + str(m.id)
	var line: HBoxContainer = kit.row(8, holder)
	var face: PanelContainer = kit.card(Color("ffe9b0"), Color.WHITE, 18, 2, 0)
	face.custom_minimum_size = Vector2(36, 36)
	face.add_child(kit.picture("", Vector2(34, 34)))
	(face.get_child(0) as TextureRect).texture = kit.HeroPortrait.texture(str(m.get("hero", "")))
	line.add_child(face)
	var words: VBoxContainer = kit.column(-2, line)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kit.stretch(kit.text(str(m.name) + (" (bạn)" if bool(m.get("me", false)) else ""), 15, kit.INK, words))
	var state: Label = kit.text("", 12, kit.MUTED, words)
	state.name = "State"
	if not bool(m.get("me", false)):
		var blocked: bool = VoiceChat.blocked.has(str(m.id))
		var mute: Button = kit.candy("Bỏ chặn" if blocked else "Tắt voice", func(): VoiceChat.toggle_block(str(m.id)); built_for = ""; refresh(), "coral" if blocked else "ghost", 13)
		mute.name = "Block"
		mute.focus_mode = Control.FOCUS_NONE
		mute.tooltip_text = "Chỉ áp dụng trong trận này"
		line.add_child(mute)
	return holder

func _process(_delta: float) -> void:
	if panel == null or not panel.visible:
		return
	# The card grows upwards from the anchor, like the chat panel.
	panel.size = Vector2(WIDTH, 0)
	panel.position = Vector2(0, -panel.get_combined_minimum_size().y)
	meter.value = VoiceChat.level if VoiceChat.talking or VoiceChat.testing else 0.0
	for holder in rows.get_children():
		var id := str(holder.name).trim_prefix("Member_")
		var state := holder.find_child("State", true, false) as Label
		var me: bool = id == str(OnlineArena.me().get("id", ""))
		if me:
			state.text = "Đang nói…" if VoiceChat.talking else ("Đã tắt mic" if VoiceChat.mic_muted else "Đang nghe")
		elif VoiceChat.blocked.has(id):
			state.text = "Bạn đã tắt voice"
		else:
			state.text = "Đang nói…" if VoiceChat.is_speaking(id) else "Đang nghe"
		var speaking: bool = state.text == "Đang nói…"
		state.add_theme_color_override("font_color", kit.MINT.darkened(0.2) if speaking else kit.MUTED)
		(holder as PanelContainer).modulate = Color(1.08, 1.08, 1.08) if speaking else Color.WHITE
