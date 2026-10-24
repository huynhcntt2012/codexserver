extends PanelContainer
## One-line voice bar for the PC waiting rooms (docs/VOICE.md): mic toggle, a
## status line (Giữ V để nói / Đang nói… / Mic đang tắt), speaker toggle and
## the voice settings. Voice itself runs while seated in an online room
## (pc_online starts VoiceChat); the seat cards light up for whoever talks.
## Offline (bot-only practice room) it only says how to get real players.

var kit: Control
var on_settings: Callable
var online := false
var offline_note := "Voice dùng khi có người thật trong phòng."
var mic_button: Button
var speaker_button: Button
var status: Label

func _init(owner_kit: Control, settings: Callable, is_online: bool) -> void:
	kit = owner_kit
	on_settings = settings
	online = is_online
	name = "VoiceStrip"
	add_theme_stylebox_override("panel", kit.box(Color("1567ae", 0.94), Color("74d3f0"), 16, 3, 6))
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _ready() -> void:
	var line: HBoxContainer = kit.row(8, self)
	mic_button = kit.round_icon("mic", func(): VoiceChat.toggle_mic(), "mint", 40)
	mic_button.name = "MicToggle"
	mic_button.focus_mode = Control.FOCUS_NONE
	line.add_child(mic_button)
	status = kit.text("", 14, Color.WHITE, line)
	status.name = "VoiceStatus"
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	speaker_button = kit.round_icon("speaker", func(): VoiceChat.toggle_deafen(), "sky", 40)
	speaker_button.name = "SpeakerToggle"
	speaker_button.focus_mode = Control.FOCUS_NONE
	line.add_child(speaker_button)
	var gear: Button = kit.round_icon("gear", func(): on_settings.call(), "ghost", 40)
	gear.name = "VoiceSettings"
	gear.tooltip_text = "Cài đặt giọng nói"
	gear.focus_mode = Control.FOCUS_NONE
	line.add_child(gear)
	mic_button.visible = online
	speaker_button.visible = online

func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var key := str(VoiceChat.setting("key"))
	if not online:
		status.text = offline_note
	elif not bool(VoiceChat.setting("enabled")):
		status.text = "Voice đang tắt (Cài đặt › Âm thanh)."
	elif VoiceChat.mic_muted:
		status.text = "Mic đang tắt · bấm nút mic để bật"
	elif VoiceChat.talking:
		status.text = "● Đang nói…"
	elif str(VoiceChat.setting("mode")) == "open":
		status.text = "Mic mở · tự gửi khi bạn nói"
	else:
		status.text = "Voice phòng · giữ %s để nói" % key
	status.add_theme_color_override("font_color", kit.MINT if VoiceChat.talking else Color.WHITE)
	mic_button.modulate.a = 0.45 if VoiceChat.mic_muted else 1.0
	mic_button.tooltip_text = "Bật mic" if VoiceChat.mic_muted else "Tắt mic"
	speaker_button.modulate.a = 0.45 if VoiceChat.deafened else 1.0
	speaker_button.tooltip_text = "Bật loa" if VoiceChat.deafened else "Tắt loa"
