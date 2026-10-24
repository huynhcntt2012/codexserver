extends SceneTree
## In-match chat and team voice on PC (docs/VOICE.md): mu-law codec, frame
## gating, playback of relayed frames and per-match mutes, the chat panel
## (badge, tabs, Enter / Esc, typing never moves or bombs), the voice panel and
## the voice settings tab. Set SUNI_CAPTURE_DIR to save screenshots.
var failed := false
var checks := 0
var capture_dir := OS.get_environment("SUNI_CAPTURE_DIR")

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error(message)

func frames(count := 2) -> void:
	for i in count:
		await process_frame

func capture(file: String) -> void:
	if capture_dir.is_empty():
		return
	await frames(3)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(capture_dir + "/" + file) == OK, "Screenshot " + file)

func key(code: Key, pressed := true) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	await frames()

func run() -> void:
	create_timer(60).timeout.connect(func(): quit(1))
	var voice = root.get_node("VoiceChat")
	# Codec: G.711 mu-law keeps speech within a few percent.
	var worst := 0.0
	for pcm in [0, 100, -100, 1000, -5000, 12000, -30000, 32767, -32768]:
		var back: int = voice.decode_ulaw(voice.encode_ulaw(pcm))
		worst = maxf(worst, absf(back - pcm) / maxf(256.0, absf(pcm)))
	check(worst < 0.07, "mu-law round trip error %.3f" % worst)
	check(voice.encode_ulaw(0) == 0xFF and voice.decode_ulaw(0xFF) == 0, "Silence is 0xFF")

	# Sending: push to talk gates the mic; silence below the gate is not sent.
	voice.active = true
	check(not voice._mic_wanted(), "PTT: mic off until the key is held")
	voice.held = true
	check(voice._mic_wanted(), "PTT: mic on while held")
	var quiet := PackedFloat32Array()
	quiet.resize(voice.FRAME)
	voice._send_frame(quiet)
	check(not voice.talking, "Silence is gated")
	var loud := PackedFloat32Array()
	for i in voice.FRAME:
		loud.append(0.4 * sin(i * 0.2))
	voice._send_frame(loud)
	check(voice.talking and voice.level > 0.5, "Speech goes out with a level")
	voice.mic_muted = true
	voice._send_frame(loud)
	check(not voice.talking, "Muted mic sends nothing")
	voice.mic_muted = false
	voice.held = false

	# Receiving: one generator per speaker, speaking state, per-match mutes.
	var frame := PackedByteArray()
	for s in loud:
		frame.append(voice._encode[int(s * 32767.0) + 32768])
	# The arena's wire format: [17, 2, channel, idLength, ...id, ...audio].
	var heard := []
	var listen := func(id, channel, audio): heard.append([id, channel, audio.size()])
	root.get_node("OnlineArena").voice_received.connect(listen)
	var packet := PackedByteArray([17, 2, 1, 2])
	packet.append_array("bo".to_utf8_buffer())
	packet.append_array(frame)
	root.get_node("OnlineArena")._handle(packet)
	root.get_node("OnlineArena").voice_received.disconnect(listen)
	check(heard == [["bo", 1, frame.size()]], "Voice packets from the arena are parsed")
	check(voice.speakers.has("bo") and voice.is_speaking("bo"), "A relayed frame plays and marks the speaker")
	voice.toggle_block("bo")
	check(not voice.speakers.has("bo"), "Blocking drops the speaker")
	root.get_node("OnlineArena").voice_received.emit("bo", 1, frame)
	check(not voice.speakers.has("bo"), "Blocked speakers stay silent")
	voice.stop()
	check(not voice.active and voice.speakers.is_empty(), "stop() clears the channel")

	# Offline match: chat panel, bots and system lines, typing guard.
	change_scene_to_file("res://scenes/main.tscn")
	await frames()
	var game = current_scene
	game.set_process(false)
	game._new_round()
	await frames(3)
	var hud = game.hud.get_node("PcBattleHud")
	var chat = hud.chat
	hud.follow_match(0.016)
	check(chat.messages.any(func(m): return m.kind == "system"), "Round start posts a system line")
	check(chat.unread > 0 and chat.badge.visible, "Unread badge on the closed chat")
	await capture("pc-chat-closed.png")
	await key(KEY_ENTER)
	await key(KEY_ENTER, false)
	check(chat.is_open() and chat.typing(), "Enter opens the chat with the input focused")
	check(chat.unread == 0 and not chat.badge.visible, "Opening reads everything")
	var bombs_before: int = game.bombs.size()
	await key(KEY_SPACE)
	await key(KEY_SPACE, false)
	check(game.bombs.size() == bombs_before, "Space while typing places no bomb")
	chat.input.text = "Hello mọi người! 👋"
	chat.submit()
	check(chat.messages.back().mine and chat.messages.back().text == "Hello mọi người! 👋" and not chat.typing(), "Sending posts the line and gives the keys back")
	hud.bot_says()
	check(chat.messages.back().kind == "player" and chat.messages.back().name.begins_with("Bot "), "Bots chat")
	chat.set_tab("system")
	check(chat.shown().all(func(m): return m.kind == "system"), "Hệ thống tab")
	chat.set_tab("team")
	check(chat.list.get_child_count() == 1, "Đội tab explains there is no team offline")
	chat.set_tab("all")
	await capture("pc-chat-open.png")
	await key(KEY_ENTER)
	await key(KEY_ESCAPE)
	check(not chat.typing() and game.game_state == "playing", "Esc leaves the input without pausing")
	await key(KEY_SPACE)
	await key(KEY_SPACE, false)
	check(game.bombs.size() == bombs_before + 1, "Space bombs again after Esc")
	chat.set_open(false)
	hud.voice.set_open(true)
	await frames()
	check(hud.voice.status.text.contains("online"), "Voice says it is for online matches")
	await capture("pc-voice-offline.png")

	# Voice settings tab.
	var page = hud.open_voice_settings()
	await frames(3)
	check(page.audio_tab == "voice" and page.find_child("VoiceKey", true, false) != null and page.find_child("MicTest", true, false) != null, "Voice settings tab")
	(page.find_child("VoiceKey", true, false) as Button).pressed.emit()
	await key(KEY_SPACE)
	check(str(page.draft.voice.key) == "V", "A match key cannot be the talk key")
	await key(KEY_B)
	check(str(page.draft.voice.key) == "B", "Rebind the talk key")
	await capture("pc-settings-voice.png")
	page.audio_tab = "general"
	game.result.get_node("PcResult").close_settings()
	print("VOICE_OK checks=%d" % checks if not failed else "VOICE_FAILED")
	quit(1 if failed else 0)
