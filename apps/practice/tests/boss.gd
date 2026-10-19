extends SceneTree
## Boss raid UI of the PC app (docs/BOSS.md) with snapshots written by the real
## arena simulation (apps/arena/scripts/boss_fixture.ts): the waiting room, the
## board with the boss, warning tiles and HP bar, the WIN result, the SĂN BOSS
## page (open / closed / rewards) and the reconnect rule. No server needed.
## Set SUNI_CAPTURE_DIR to save screenshots (needs a display).
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

func frames(n := 3) -> void:
	for i in n:
		await process_frame

func capture(file: String) -> void:
	if capture_dir.is_empty():
		return
	await frames(6)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture_dir + "/" + file)

func boss_event(open: bool) -> Dictionary:
	return {
		"id": "evt_ui", "name": "Đại Chiến Boss - Săn Boss Nhận Quà", "description": "", "banner": "Một sinh vật bí ẩn xuất hiện!",
		"intro": "Lập đội săn Boss.", "badge_name": "Huy Hiệu Boss", "phase": "running", "window": "progress",
		"start_at": "2026-10-19T00:00:00+00:00", "end_at": "2026-10-26T00:00:00+00:00", "claim_end_at": "2026-10-29T00:00:00+00:00",
		"open": open, "in_session": open, "next_session": "2026-10-19T12:00:00+00:00", "server_time": "2026-10-19T08:00:00+00:00",
		"rules": {
			"display_name": "Boss Sự Kiện", "map_id": "harbor", "min_players": 1, "max_players": 8, "duration_seconds": 300,
			"hp_solo": 1000, "hp_full": 4850, "phase_thresholds": [0.7, 0.35], "skills": ["boss_basic_hit", "boss_aoe_mark"],
			"items": ["dart"], "mount": true, "reward_private_room": false, "full_reward_limit_per_day": 3,
			"win_rewards": [{"type": "gold", "amount": 150}, {"type": "token", "amount": 30, "label": "Huy Hiệu Boss"}],
			"lose_rewards": [{"type": "gold", "amount": 20}], "sessions": [{"days_of_week": [1, 2, 3, 4, 5, 6, 7], "local_start": "19:00", "local_end": "22:00"}],
		},
		"me": {"wins": 2, "full_rewards_today": 1, "pending_rewards": 1, "badges": 60},
		"quests": [], "shop": [],
	}

func run() -> void:
	create_timer(120).timeout.connect(func(): push_error("timeout"); quit(1))
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/boss_snapshots.json"))
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(4)
	var arena = root.get_node("OnlineArena")
	arena.session_id = "me"
	game.show_pc_screen("online")
	var online = game.pc_screens["online"]
	await frames()

	# Waiting room: boss title, solo allowed, seats from the event.
	arena.snapshot = fixtures.waiting
	online._on_snapshot(fixtures.waiting)
	await frames()
	check(online.title_label.text.contains("Đại Chiến Boss") and online.title_label.text.contains("Boss Sự Kiện"), "Room title names the boss: " + online.title_label.text)
	check(online.status_label.text.contains("Tối thiểu 1"), "Solo raids allowed: " + online.status_label.text)
	check(not online.ready_button.disabled, "Ready while waiting")
	await capture("boss-room.png")

	# Playing: boss on its footprint, the telegraph tiles of the server, HP bar.
	arena.snapshot = fixtures.playing
	online._on_snapshot(fixtures.playing)
	await frames()
	var boss: Dictionary = fixtures.playing.boss
	check(online.battle_view.visible and online.boss_view.visible and online.boss_hud.visible, "Boss board and HUD shown")
	check(online.boss_view.boss.get("casts", []).size() == 1, "The server's cast is drawn")
	check(online.boss_view.boss.casts[0].tiles == boss.casts[0].tiles, "Same warning tiles as the server")
	check(online.boss_title.text == "Boss Sự Kiện" and online.boss_phase.text == "PHASE 1", "Boss name and phase")
	check(is_equal_approx(online.boss_bar.hp, float(boss.hp)) and online.boss_bar.thresholds == boss.thresholds, "HP bar and phase ticks")
	check(online.boss_note.text.begins_with("⚠"), "Current skill named: " + online.boss_note.text)
	check(online.stat_status.text.contains("Boss"), "Boss hint in the status bar")
	var footprint: Rect2 = online.boss_view.footprint()
	check(footprint.position == Vector2(7, 5) * 64 and footprint.size == Vector2(192, 192), "Footprint 3x3 at (7,5)")
	check(online.boss_view.art != null and online.boss_view.current_anim() == "cast", "Slime King art, casting pose during a telegraph")
	check(online.boss_view.throws_slimes(boss.casts[0]) and not online.boss_view.minis.mini_bomb.is_empty(), "The boss throws mini slimes at the warned cells")
	# Grows and shrinks, but never leaves its 3x3 footprint (phase 3, mid-throw too).
	var view = online.boss_view
	var widths := []
	for phase in [1, 3]:
		view.boss.phase = phase
		for kick in [0.0, 0.175]:
			view.throw_kick = kick
			for i in 40:
				view.clock = i * 0.07
				for anim in ["idle", "cast", "move", "defeat"]:
					var size: Vector2 = view.art_size(view.textures.idle, anim)
					widths.append(size.x)
					check(size.x <= 192.01 and size.y <= 192.01, "%s fits 3x3 at phase %d: %s" % [anim, phase, size])
	view.boss.phase = 1
	view.throw_kick = 0.0
	check(widths.max() > widths.min() * 1.15, "The boss grows and shrinks: %d..%d px" % [widths.min(), widths.max()])
	await create_timer(1.6).timeout
	var cast: Dictionary = boss.casts[0]
	online.boss_view.now = float(cast.castAt) + 200.0  # slimes in the air
	online.boss_view.set_process(false)
	online.boss_view.queue_redraw()
	await capture("boss-throw.png")
	online.boss_view.now = float(cast.resolveAt) - 150.0  # landed, about to burst
	online.boss_view.queue_redraw()
	await capture("boss-battle.png")
	online.boss_view.set_process(true)

	# Finished WIN: server result, then the API result (none offline).
	arena.snapshot = fixtures.finished
	online._on_snapshot(fixtures.finished)
	await frames()
	check(online.result_box.visible and online.result_title.text == "ĐÃ HẠ BOSS!", "WIN result from the snapshot")
	check(online.boss_view.current_anim() == "defeat" and online.boss_view.defeat_time >= 0.0, "Defeat effect starts when HP reaches 0")
	check(online.boss_view.art == online.boss_view.textures.idle, "Same Slime King art in every state")
	check(online.boss_view.bursts.size() == 1 and online.boss_view.bursts[0].kind == "mini_bomb", "Thrown slimes burst when the server resolves the hit")
	check(online.raid_match == "p1.fixture.1", "Fetches the result of this raid id")
	check(not online.claim_button.visible, "No claim button before the server says so")
	online.raid_info = {"me": {"damage": 50, "support": 0, "reward": "full", "reason": ""}, "grants": [{"id": "g1", "status": "ELIGIBLE", "kind": "full", "rewards": [{"type": "gold", "amount": 150}]}]}
	online.render_side(fixtures.finished)
	check(online.claim_button.visible and online.result_detail.text.contains("150 xu"), "Claim offered for an eligible grant")
	online.raid_info = {"me": {"damage": 0, "support": 0, "reward": "none", "reason": "AFK", "reason_text": "Không hoạt động (AFK)"}, "grants": []}
	online.render_side(fixtures.finished)
	check(not online.claim_button.visible and online.result_detail.text.contains("AFK"), "Ineligible shows the reason")
	online.result_box.hide()
	for spec in [[0.3, "boss-defeat-1.png"], [0.75, "boss-defeat-2.png"], [1.3, "boss-defeat-3.png"]]:
		online.boss_view.set_process(false)
		online.boss_view.defeat_time = spec[0]
		online.boss_view.queue_redraw()
		await capture(spec[1])
	online.boss_view.set_process(true)
	online.render_side(fixtures.finished)
	await capture("boss-result.png")

	# Reconnect only for a boss raid in play, with the JOIN_ROOM token.
	arena.snapshot = fixtures.playing
	arena._reconnect_token = "abc"
	check(arena._resumable(), "A dropped boss raid is resumed")
	arena.snapshot = fixtures.finished
	check(not arena._resumable(), "No resume after the raid")
	arena._reconnect_token = ""
	arena.snapshot = {}

	# SĂN BOSS page (popup of the lobby): open event -> three ways in; closed -> disabled.
	game.show_pc_screen("lobby")
	var lobby = game.pc_screens["lobby"]
	var page = lobby.store_page("boss")
	lobby.open_shop("boss")
	await frames()
	check(lobby.store_title.text == "ĐẠI CHIẾN BOSS", "Boss popup title")
	var played := []
	# The lobby would join the arena; record the request instead.
	page.play.disconnect(lobby.play_boss)
	page.play.connect(func(event_id, mode): played.append([event_id, mode]))
	page.state = "ok"
	page.events = [boss_event(true)]
	page.render()
	await frames()
	var solo: Button = page.find_child("Play_solo", true, false)
	var team: Button = page.find_child("Play_team", true, false)
	check(solo != null and not solo.disabled and not team.disabled, "Open event: Solo / Ghép đội enabled")
	solo.pressed.emit()
	team.pressed.emit()
	check(played == [["evt_ui", "solo"], ["evt_ui", "team"]], "Buttons ask the lobby to join: %s" % [played])
	var private_button: Button = page.find_child("Play_private", true, false)
	private_button.pressed.emit()
	check(page.modal.visible and played.size() == 2, "Private room warns about rewards first")
	page.close_modal()
	check(page.tokens_label.text.contains("60"), "Badge balance shown")
	page.events = [boss_event(false)]
	page.render()
	await frames()
	solo = page.find_child("Play_solo", true, false)
	check(solo.disabled, "Closed event: no new raid")
	page.rewards = [{"id": "g1", "kind": "full", "status": "ELIGIBLE", "rewards": [{"type": "gold", "amount": 150}]}]
	page.set_tab("rewards")
	await frames()
	check(page.find_child("Grant_g1", true, false) != null, "Pending raid reward listed")
	page.set_tab("raid")
	page.events = [boss_event(true)]
	page.render()
	await capture("boss-page.png")
	if not failed:
		print("BOSS_UI_OK checks=", checks)
	quit(1 if failed else 0)
