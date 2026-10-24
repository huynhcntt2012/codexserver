extends Node
## Team voice in online matches (docs/VOICE.md), PC app only. The microphone is
## captured from a muted "VoiceMic" bus, averaged down to 16 kHz mono, gated,
## mu-law encoded and sent in 60 ms frames through the arena WebSocket
## (OnlineArena.send_voice). Frames from others are decoded into one
## AudioStreamGenerator per speaker on the "Voice" bus. The arena names the
## speaker; nothing is recorded or stored.
##
## Push-to-talk ("ptt") opens the mic only while the key is held; open mic
## ("open") keeps it on during the match and sends speech above the
## sensitivity. The match screen calls start() / stop(); the settings window
## uses start_test() for its level meter.
signal speaking_changed(id: String, speaking: bool)
signal talking_changed(talking: bool)

const RATE := 16000
const FRAME := 960  # 60 ms
const CHANNELS := {"team": 0, "all": 1}
const SPEAKING_SECONDS := 0.35
const BIAS := 0x84
const CLIP := 32635

var active := false  # in an online match with voice enabled
var testing := false  # settings mic test: meter only, nothing is sent
var mic_muted := false  # the mic button in the voice panel
var deafened := false  # the speaker button: hear nobody
var held := false  # push-to-talk key down
var talking := false  # a frame is going out (or would, in a test)
var level := 0.0  # own mic level 0..1 (meter)
## Per-match mutes, by arena session id (the "chặn giọng nói" list).
var blocked: Dictionary = {}
## id -> {player, playback, heard, level}
var speakers: Dictionary = {}

var _capture: AudioEffectCapture
var _mic: AudioStreamPlayer
var _encode := PackedByteArray()
var _decode := PackedFloat32Array()
var _step := 3.0
var _acc := 0.0
var _acc_n := 0.0
var _frame := PackedFloat32Array()
var _tail := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_tables()
	for name in ["VoiceMic", "Voice"]:
		if AudioServer.get_bus_index(name) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, name)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	var mic_bus := AudioServer.get_bus_index("VoiceMic")
	AudioServer.set_bus_mute(mic_bus, true)  # never play our own mic back
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 0.5
	AudioServer.add_bus_effect(mic_bus, _capture)
	_mic = AudioStreamPlayer.new()
	_mic.stream = AudioStreamMicrophone.new()
	_mic.bus = "VoiceMic"
	add_child(_mic)
	_step = AudioServer.get_mix_rate() / float(RATE)
	OnlineArena.voice_received.connect(_on_voice)
	OnlineArena.closed.connect(func(_reason): stop())

func setting(key: String):
	return Settings.get_value("voice", key)

func channel() -> int:
	return CHANNELS.get(str(setting("channel")), 1)

## The keycode of the push-to-talk key (settings voice.key, default V).
func talk_key() -> Key:
	var code := OS.find_keycode_from_string(str(setting("key")))
	return code if code != KEY_NONE else KEY_V

func start() -> void:
	active = bool(setting("enabled"))
	blocked.clear()
	_sync_mic()

func stop() -> void:
	active = false
	held = false
	for id in speakers.keys():
		_drop_speaker(id)
	_sync_mic()

func start_test() -> void:
	testing = true
	_sync_mic()

func stop_test() -> void:
	testing = false
	_sync_mic()

func toggle_mic() -> void:
	mic_muted = not mic_muted
	_sync_mic()

func toggle_deafen() -> void:
	deafened = not deafened
	for id in speakers:
		speakers[id].player.stream_paused = deafened

func toggle_block(id: String) -> void:
	if blocked.has(id):
		blocked.erase(id)
	else:
		blocked[id] = true
		_drop_speaker(id)

func is_speaking(id: String) -> bool:
	return speakers.has(id) and Time.get_ticks_msec() / 1000.0 - float(speakers[id].heard) < SPEAKING_SECONDS

## The mic runs only when it can send (or in the settings test): with push to
## talk that is while the key is held, so the OS mic light shows only then.
func _mic_wanted() -> bool:
	if testing:
		return true
	if not active or mic_muted:
		return false
	return held or str(setting("mode")) == "open"

func _sync_mic() -> void:
	var want := _mic_wanted()
	if want and not _mic.playing:
		_capture.clear_buffer()
		_frame.clear()
		_mic.play()
	elif not want and _mic.playing and _tail <= 0.0:
		_mic.stop()
		level = 0.0
		_set_talking(false)

func _input(event: InputEvent) -> void:
	if not active or not (event is InputEventKey) or event.echo:
		return
	if (event as InputEventKey).keycode != talk_key() or str(setting("mode")) != "ptt":
		return
	var focus := get_viewport().gui_get_focus_owner()
	if event.pressed and (focus is LineEdit or focus is TextEdit):
		return  # typing a "v" in chat
	held = event.pressed
	if not held:
		_tail = 0.15  # let the last syllable out
	_sync_mic()

func _process(delta: float) -> void:
	if _tail > 0.0:
		_tail -= delta
		if _tail <= 0.0:
			_sync_mic()
	for id in speakers:
		var speaking := is_speaking(id)
		if speaking != bool(speakers[id].get("was", false)):
			speakers[id].was = speaking
			speaking_changed.emit(id, speaking)
	if not _mic.playing:
		return
	var available := _capture.get_frames_available()
	if available <= 0:
		return
	var gain: float = float(setting("mic_volume")) / 80.0
	var buffer := _capture.get_buffer(available)
	for v in buffer:
		_acc += (v.x + v.y) * 0.5
		_acc_n += 1.0
		if _acc_n >= _step:
			_frame.append(clampf(_acc / _acc_n * gain, -1.0, 1.0))
			_acc = 0.0
			_acc_n -= _step
			if _frame.size() >= FRAME:
				_send_frame(_frame)
				_frame.clear()

func _send_frame(samples: PackedFloat32Array) -> void:
	var sum := 0.0
	for s in samples:
		sum += s * s
	var rms := sqrt(sum / samples.size())
	level = clampf(rms * 6.0, 0.0, 1.0)
	# Sensitivity 0..100: higher picks up quieter speech.
	var gate := 0.12 * (1.0 - float(setting("sensitivity")) / 100.0) + 0.004
	var open_mic := str(setting("mode")) == "open"
	var loud := rms >= gate if (open_mic or bool(setting("noise_gate"))) else true
	if testing:
		_set_talking(loud)
		return
	var sending := loud and (held or _tail > 0.0 or open_mic) and not mic_muted
	_set_talking(sending)
	if not sending:
		return
	var out := PackedByteArray()
	out.resize(samples.size())
	for i in samples.size():
		out[i] = _encode[int(samples[i] * 32767.0) + 32768]
	OnlineArena.send_voice(channel(), out)

func _set_talking(value: bool) -> void:
	if talking != value:
		talking = value
		talking_changed.emit(value)

func _on_voice(id: String, _channel: int, audio: PackedByteArray) -> void:
	if not active or blocked.has(id) or id == str(OnlineArena.me().get("id", "")):
		return
	if not speakers.has(id):
		var player := AudioStreamPlayer.new()
		var stream := AudioStreamGenerator.new()
		stream.mix_rate = RATE
		stream.buffer_length = 0.4
		player.stream = stream
		player.bus = "Voice"
		add_child(player)
		player.play()
		player.stream_paused = deafened
		speakers[id] = {"player": player, "playback": player.get_stream_playback(), "heard": 0.0, "level": 0.0}
	var entry: Dictionary = speakers[id]
	entry.player.volume_db = linear_to_db(maxf(0.001, float(setting("voice_volume")) / 100.0))
	var frames := PackedVector2Array()
	frames.resize(audio.size())
	var sum := 0.0
	for i in audio.size():
		var s := _decode[audio[i]]
		sum += s * s
		frames[i] = Vector2(s, s)
	entry.heard = Time.get_ticks_msec() / 1000.0
	entry.level = clampf(sqrt(sum / maxf(1.0, audio.size())) * 6.0, 0.0, 1.0)
	var playback := entry.playback as AudioStreamGeneratorPlayback
	if playback and not deafened and playback.can_push_buffer(frames.size()):
		playback.push_buffer(frames)

func _drop_speaker(id: String) -> void:
	if speakers.has(id):
		(speakers[id].player as Node).queue_free()
		speakers.erase(id)
		speaking_changed.emit(id, false)

## G.711 mu-law: 16-bit sample (offset by 32768) -> byte, and byte -> float.
func _build_tables() -> void:
	_encode.resize(65536)
	for i in 65536:
		_encode[i] = encode_ulaw(i - 32768)
	_decode.resize(256)
	for b in 256:
		_decode[b] = decode_ulaw(b) / 32768.0

static func encode_ulaw(pcm: int) -> int:
	var sign := 0
	if pcm < 0:
		sign = 0x80
		pcm = -pcm
	pcm = mini(pcm, CLIP) + BIAS
	var exponent := 7
	var mask := 0x4000
	while exponent > 0 and (pcm & mask) == 0:
		exponent -= 1
		mask >>= 1
	var mantissa := (pcm >> (exponent + 3)) & 0x0F
	return ~(sign | (exponent << 4) | mantissa) & 0xFF

static func decode_ulaw(byte: int) -> int:
	byte = ~byte & 0xFF
	var sample := (((byte & 0x0F) << 3) + BIAS) << ((byte >> 4) & 0x07)
	sample -= BIAS
	return -sample if byte & 0x80 else sample
